#!/bin/bash

###### 使用方法 ######
# ./worktree.sh <branchName> # 指定した名前のブランチに対応するworktreeに移動
# ./worktree.sh -b <branchName> # 指定した名前でブランチを作成、また {branchName}-{repoName} の形式でworktreeディレクトリを作成し移動
# ./worktree.sh -r <branchName> # 指定した名前のブランチを削除、また {branchName}_{repoName} の形式でworktreeディレクトリを削除
# ./worktree.sh -r <pr_number> # 指定したPR番号に対応するブランチを削除、また pr-{pr_number}_{repoName} の形式でworktreeディレクトリを削除
# ./worktree.sh -p <pr_number> # 指定したPR番号のブランチをチェックアウトし、pr-{pr_number}_{repoName} の形式でworktreeディレクトリを作成し移動
#####################

# 現在のGitリポジトリのルートディレクトリを取得
CURRENT_REPO_ROOT=$(git rev-parse --show-toplevel)
CURRENT_REPO_NAME=$(basename "$CURRENT_REPO_ROOT")

BASE_BRANCH=main
# スクリプトのディレクトリ
SCRIPT_DIR=$(dirname "$0")
# リポジトリの親ディレクトリ
PARENT_DIR=$(dirname "$CURRENT_REPO_ROOT")

# 共通関数定義

# worktreeパスを生成する関数
generate_worktree_path() {
  local prefix="$1"
  local identifier="$2"
  local repo_name="$3"
  
  if [ "$prefix" = "pr" ]; then
    echo "${PARENT_DIR}/pr-${identifier}_${repo_name}"
  else
    echo "${PARENT_DIR}/${identifier}_${repo_name}"
  fi
}

# エラーメッセージを出力して終了する関数
error_exit() {
  echo "Error: $1"
  exit 1
}

# 成功メッセージを出力する関数
success_message() {
  echo "$1"
}

# ディレクトリに移動する関数
change_directory() {
  local target_dir="$1"
  exec "$SHELL" -c "cd \"$target_dir\" && exec \"$SHELL\""
}

# worktreeディレクトリの存在をチェックする関数
check_worktree_exists() {
  local worktree_path="$1"
  local should_exist="$2"  # true/false
  
  if [ "$should_exist" = "true" ]; then
    if [ ! -d "$worktree_path" ]; then
      return 1
    fi
  else
    if [ -d "$worktree_path" ]; then
      return 1
    fi
  fi
  return 0
}

# 現在のworktreeから移動が必要かチェックし、必要なら移動する関数
check_and_move_if_current_worktree() {
  local target_name="$1"
  local worktree_type="$2"  # "pr" or "branch"
  
  local should_move=false
  
  if [ "$worktree_type" = "pr" ]; then
    local expected_name="pr-${target_name}_${BASE_REPO_NAME}"
    if [ "${CURRENT_REPO_NAME}" = "${expected_name}" ]; then
      should_move=true
    fi
  else
    local current_prefix="${CURRENT_REPO_NAME%%_*}"
    if [ "${current_prefix}" = "${target_name}" ]; then
      should_move=true
    fi
  fi
  
  if [ "$should_move" = "true" ]; then
    echo "ディレクトリ ${PARENT_DIR}/${BASE_REPO_NAME} に移動します。移動後もう一度実行してください。"
    change_directory "${PARENT_DIR}/${BASE_REPO_NAME}"
    exit 0
  fi
}

# worktreeを削除する関数
remove_worktree() {
  local worktree_name="$1"
  
  git worktree remove "$worktree_name"
  if [ $? -ne 0 ]; then
    error_exit "worktreeディレクトリの削除に失敗しました。"
  else
    success_message "worktreeディレクトリを削除しました。"
  fi
}

# ブランチを削除する関数
remove_branch() {
  local branch_name="$1"
  local force="$2"  # "-d" or "-D"
  
  git branch ${force:-"-d"} "$branch_name"
  if [ $? -ne 0 ]; then
    error_exit "ブランチ ${branch_name} の削除に失敗しました。"
  fi
  success_message "ブランチ ${branch_name} を削除しました。"
}

# worktree ディレクトリかどうかを判定する
if [ "$(git rev-parse --git-dir)" = ".git" ]; then
  IS_WORKTREE=false
  BASE_REPO_NAME="${CURRENT_REPO_NAME}"
else
  IS_WORKTREE=true
  BASE_REPO_NAME="${CURRENT_REPO_NAME#*_}"
fi

# 1. 現在のリポジトリがGitリポジトリであるかをチェック。Git リポジトリでなければ実行終了
if [ -z "$CURRENT_REPO_ROOT" ]; then
  error_exit "Gitリポジトリではありません。"
fi



# サブコマンドの処理
case "$1" in
  "-p")
    # PRモード
    PR_NUMBER="$2"
    
    if [ -z "$PR_NUMBER" ]; then
      error_exit "PR番号を指定してください。\n使用方法: ./worktree.sh -p <pr_number>"
    fi
    
    # PR番号が数値であることを確認
    if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
      error_exit "PR番号は数値である必要があります。"
    fi
    
    # pr-{pr_number}_{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_PATH=$(generate_worktree_path "pr" "$PR_NUMBER" "$BASE_REPO_NAME")
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")
    
    if ! check_worktree_exists "$WORKTREE_PATH" "false"; then
      error_exit "既に ${WORKTREE_PATH} ディレクトリが存在します。"
    fi
    
    echo "PR #${PR_NUMBER} のブランチをチェックアウトしています..."
    
    # gh pr checkout を使用してPRブランチをチェックアウト
    if ! command -v gh >/dev/null 2>&1; then
      error_exit "GitHub CLI (gh) がインストールされていません。\nGitHub CLI をインストールしてください: https://cli.github.com/"
    fi
    
    # PR情報を取得してブランチ名を確認
    PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$PR_BRANCH" ]; then
      error_exit "PR #${PR_NUMBER} が見つかりません。"
    fi
    
    echo "worktreeを ${WORKTREE_PATH} に作成します..."
    
    # worktreeを作成してPRブランチをチェックアウト
    git worktree add "$WORKTREE_PATH"
    if [ $? -ne 0 ]; then
      error_exit "worktreeの作成に失敗しました。"
    fi
    
    # worktreeディレクトリでPRをチェックアウト
    cd "$WORKTREE_PATH"
    gh pr checkout "$PR_NUMBER"
    if [ $? -ne 0 ]; then
      # 失敗した場合はworktreeを削除
      cd "$CURRENT_REPO_ROOT"
      git worktree remove "$WORKTREE_PATH"
      error_exit "PR #${PR_NUMBER} のチェックアウトに失敗しました。"
    fi
    
    success_message "worktreeを正常に作成しました。"
    echo "worktreeディレクトリ: ${WORKTREE_PATH}"
    echo "PRブランチ: ${PR_BRANCH}"
    
    # 該当ブランチへ移動
    change_directory "$WORKTREE_PATH"
    ;;
  "-b")
    # 作成モード
    TARGET_BRANCH="$2"

    # ブランチ名に _ が含まれていた場合、エラーとする
    if echo "$TARGET_BRANCH" | grep -q "_"; then
      error_exit "ブランチ名に _ が含まれています。ブランチ名には _ を使用しないでください。"
    fi

    # {branchName}_{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_PATH=$(generate_worktree_path "branch" "$TARGET_BRANCH" "$BASE_REPO_NAME")
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")

    if ! check_worktree_exists "$WORKTREE_PATH" "false"; then
      error_exit "既に ${WORKTREE_PATH} ディレクトリが存在します。\n既存のworktreeを削除するには './worktree.sh -r ${TARGET_BRANCH}' を使用してください。"
    fi

    # ブランチが存在するかをチェックし、存在していたらエラーを返す
    if git branch --list "$TARGET_BRANCH" | grep -q "$TARGET_BRANCH"; then
      error_exit "既存のブランチ ${TARGET_BRANCH} が存在します。"
    fi

    echo "worktreeを ${WORKTREE_PATH} に作成します..."
    git worktree add "$WORKTREE_PATH" -b "$TARGET_BRANCH"
    if [ $? -ne 0 ]; then
      error_exit "worktreeの作成に失敗しました。"
    fi
    success_message "worktreeを正常に作成しました。"
    echo "worktreeディレクトリ: ${WORKTREE_PATH}"

    # 該当ブランチへ移動
    change_directory "$WORKTREE_PATH"
    ;;
  "-r")
    # 削除モード
    TARGET_BRANCH="$2"
    
    # PR番号かどうかを判定（数値のみの場合はPR番号とみなす）
    if [[ "$TARGET_BRANCH" =~ ^[0-9]+$ ]]; then
      # PR番号の場合
      PR_NUMBER="$TARGET_BRANCH"
      WORKTREE_PATH=$(generate_worktree_path "pr" "$PR_NUMBER" "$BASE_REPO_NAME")
      WORKTREE_NAME=$(basename "$WORKTREE_PATH")
      
      if check_worktree_exists "$WORKTREE_PATH" "true"; then
        echo "PR #${PR_NUMBER} のworktreeディレクトリ ${WORKTREE_PATH} を削除します..."
        
        # 現在のworktreeからの移動が必要かチェック
        check_and_move_if_current_worktree "$PR_NUMBER" "pr"
        
        remove_worktree "$WORKTREE_NAME"
        
        # PR対応のブランチ名を取得して削除
        # worktreeディレクトリが削除された後なので、git branchで確認
        cd "${PARENT_DIR}/${BASE_REPO_NAME}"
        
        # PRに対応するローカルブランチを探して削除
        # gh pr view でブランチ名を取得
        if command -v gh >/dev/null 2>&1; then
          PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null)
          if [ $? -eq 0 ] && [ -n "$PR_BRANCH" ]; then
            # ローカルブランチが存在するかチェック
            if git branch --list "$PR_BRANCH" | grep -q "$PR_BRANCH"; then
              remove_branch "$PR_BRANCH" "-D"
            fi
          fi
        fi
      else
        error_exit "PR #${PR_NUMBER} のworktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
      fi
    else
      # 通常のブランチ名の場合
      WORKTREE_PATH=$(generate_worktree_path "branch" "$TARGET_BRANCH" "$BASE_REPO_NAME")
      WORKTREE_NAME=$(basename "$WORKTREE_PATH")

      if check_worktree_exists "$WORKTREE_PATH" "true"; then
        echo "worktreeディレクトリ ${WORKTREE_PATH} とブランチ ${TARGET_BRANCH} を削除します..."
        # 現在のworktreeからの移動が必要かチェック
        check_and_move_if_current_worktree "$TARGET_BRANCH" "branch"
        
        remove_worktree "$WORKTREE_NAME"
        
        # ブランチを削除
        remove_branch "$TARGET_BRANCH"
      else
        error_exit "worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
      fi
    fi
    ;;
  *)
    # 移動モード (オプションなし)
    TARGET_BRANCH="$1"

    # BASE_BRANCH の場合、 cd で移動するのみを行う
    if [ "$TARGET_BRANCH" = "$BASE_BRANCH" ]; then
      change_directory "${PARENT_DIR}/${BASE_REPO_NAME}"
      exit 0
    fi

    WORKTREE_PATH=$(generate_worktree_path "branch" "$TARGET_BRANCH" "$BASE_REPO_NAME")

    if ! check_worktree_exists "$WORKTREE_PATH" "true"; then
      error_exit "worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。\n${TARGET_BRANCH} ブランチのworktreeを作成するには './worktree.sh -b ${TARGET_BRANCH}' を使用してください。"
    fi

    # worktreeディレクトリに移動
    echo "${WORKTREE_PATH} に移動します..."
    change_directory "$WORKTREE_PATH"
esac
