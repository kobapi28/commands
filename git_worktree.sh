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
  echo "エラー: Gitリポジトリではありません。"
  exit 1
fi



# サブコマンドの処理
case "$1" in
  "-p")
    # PRモード
    PR_NUMBER="$2"
    
    if [ -z "$PR_NUMBER" ]; then
      echo "Error: PR番号を指定してください。"
      echo "使用方法: ./worktree.sh -p <pr_number>"
      exit 1
    fi
    
    # PR番号が数値であることを確認
    if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "Error: PR番号は数値である必要があります。"
      exit 1
    fi
    
    # pr-{pr_number}_{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_NAME="pr-${PR_NUMBER}_${BASE_REPO_NAME}"
    WORKTREE_PATH="${PARENT_DIR}/${WORKTREE_NAME}"
    
    if [ -d "$WORKTREE_PATH" ]; then
      echo "Error: 既に ${WORKTREE_PATH} ディレクトリが存在します。"
      exit 1
    fi
    
    echo "PR #${PR_NUMBER} のブランチをチェックアウトしています..."
    
    # gh pr checkout を使用してPRブランチをチェックアウト
    if ! command -v gh >/dev/null 2>&1; then
      echo "Error: GitHub CLI (gh) がインストールされていません。"
      echo "GitHub CLI をインストールしてください: https://cli.github.com/"
      exit 1
    fi
    
    # PR情報を取得してブランチ名を確認
    PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$PR_BRANCH" ]; then
      echo "Error: PR #${PR_NUMBER} が見つかりません。"
      exit 1
    fi
    
    echo "worktreeを ${WORKTREE_PATH} に作成します..."
    
    # worktreeを作成してPRブランチをチェックアウト
    git worktree add "$WORKTREE_PATH"
    if [ $? -ne 0 ]; then
      echo "Error: worktreeの作成に失敗しました。"
      exit 1
    fi
    
    # worktreeディレクトリでPRをチェックアウト
    cd "$WORKTREE_PATH"
    gh pr checkout "$PR_NUMBER"
    if [ $? -ne 0 ]; then
      echo "Error: PR #${PR_NUMBER} のチェックアウトに失敗しました。"
      # 失敗した場合はworktreeを削除
      cd "$CURRENT_REPO_ROOT"
      git worktree remove "$WORKTREE_PATH"
      exit 1
    fi
    
    echo "worktreeを正常に作成しました。"
    echo "worktreeディレクトリ: ${WORKTREE_PATH}"
    echo "PRブランチ: ${PR_BRANCH}"
    
    # 該当ブランチへ移動
    exec "$SHELL" -c "cd \"$WORKTREE_PATH\" && exec \"$SHELL\""
    ;;
  "-b")
    # 作成モード
    TARGET_BRANCH="$2"

    # ブランチ名に _ が含まれていた場合、エラーとする
    if echo "$TARGET_BRANCH" | grep -q "_"; then
      echo "Error: ブランチ名に _ が含まれています。ブランチ名には _ を使用しないでください。"
      exit 1
    fi

    # {branchName}_{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_NAME="${TARGET_BRANCH}_${BASE_REPO_NAME}"
    WORKTREE_PATH="${PARENT_DIR}/${WORKTREE_NAME}"

    if [ -d "$WORKTREE_PATH" ]; then
      echo "Error: 既に ${WORKTREE_PATH} ディレクトリが存在します。"
      echo "既存のworktreeを削除するには './worktree.sh -r ${TARGET_BRANCH}' を使用してください。"
      exit 1
    fi

    # ブランチが存在するかをチェックし、存在していたらエラーを返す
    if git branch --list "$TARGET_BRANCH" | grep -q "$TARGET_BRANCH"; then
      echo "Error: 既存のブランチ ${TARGET_BRANCH} が存在します。"
      exit 1
    fi

    echo "worktreeを ${WORKTREE_PATH} に作成します..."
    git worktree add "$WORKTREE_PATH" -b "$TARGET_BRANCH"
    if [ $? -ne 0 ]; then
      echo "Error: worktreeの作成に失敗しました。"
      exit 1
    fi
    echo "worktreeを正常に作成しました。"
    echo "worktreeディレクトリ: ${WORKTREE_PATH}"

    # 該当ブランチへ移動
    exec "$SHELL" -c "cd \"$WORKTREE_PATH\" && exec \"$SHELL\""
    echo "ブランチ ${TARGET_BRANCH} に移動しました。"
    ;;
  "-r")
    # 削除モード
    TARGET_BRANCH="$2"
    
    # PR番号かどうかを判定（数値のみの場合はPR番号とみなす）
    if [[ "$TARGET_BRANCH" =~ ^[0-9]+$ ]]; then
      # PR番号の場合
      PR_NUMBER="$TARGET_BRANCH"
      WORKTREE_NAME="pr-${PR_NUMBER}_${BASE_REPO_NAME}"
      WORKTREE_PATH="${PARENT_DIR}/${WORKTREE_NAME}"
      
      if [ -d "$WORKTREE_PATH" ]; then
        echo "PR #${PR_NUMBER} のworktreeディレクトリ ${WORKTREE_PATH} を削除します..."
        
        # CURRENT_REPO_NAME が pr-{PR_NUMBER}_{BASE_REPO_NAME} の場合は、元となるディレクトリに移動してから実行する
        if [ "${CURRENT_REPO_NAME}" = "${WORKTREE_NAME}" ]; then
          echo "ディレクトリ ${PARENT_DIR}/${BASE_REPO_NAME} に移動します。移動後もう一度実行してください。"
          exec "$SHELL" -c "cd \"${PARENT_DIR}/${BASE_REPO_NAME}\" && exec \"$SHELL\""
          exit 0
        fi
        
        git worktree remove "$WORKTREE_NAME"
        if [ $? -ne 0 ]; then
          echo "Error: worktreeディレクトリの削除に失敗しました。"
          exit 1
        else
          echo "worktreeディレクトリを削除しました。"
        fi
        
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
              git branch -D "$PR_BRANCH"
              if [ $? -eq 0 ]; then
                echo "ブランチ ${PR_BRANCH} を削除しました。"
              else
                echo "Warning: ブランチ ${PR_BRANCH} の削除に失敗しました。"
              fi
            fi
          fi
        fi
      else
        echo "Error: PR #${PR_NUMBER} のworktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
        exit 1
      fi
    else
      # 通常のブランチ名の場合
      WORKTREE_NAME="${TARGET_BRANCH}_${BASE_REPO_NAME}"
      WORKTREE_PATH="${PARENT_DIR}/${WORKTREE_NAME}"

      if [ -d "$WORKTREE_PATH" ]; then
        echo "worktreeディレクトリ ${WORKTREE_PATH} とブランチ ${TARGET_BRANCH} を削除します..."
        # CURRENT_REPO_NAME の最初の _ までの文字列と受け取った TARGET_BRANCH が一致している場合は、元となるディレクトリに移動してから実行する
        CURRENT_REPO_NAME_PREFIX="${CURRENT_REPO_NAME%%_*}"
        if [ "${CURRENT_REPO_NAME_PREFIX}" = "${TARGET_BRANCH}" ]; then
          echo "ディレクトリ ${PARENT_DIR}/${BASE_REPO_NAME} に移動します。移動後もう一度実行してください。"
          exec "$SHELL" -c "cd \"${PARENT_DIR}/${BASE_REPO_NAME}\" && exec \"$SHELL\""
          exit 0
        fi
        git worktree remove "$WORKTREE_NAME"
        if [ $? -ne 0 ]; then
          echo "Error: worktreeディレクトリの削除に失敗しました。"
          exit 1
        else
          echo "worktreeディレクトリを削除しました。"
        fi
        
        # ブランチを削除
        git branch -d "$TARGET_BRANCH"
        if [ $? -ne 0 ]; then
            echo "Error: ブランチ ${TARGET_BRANCH} の削除に失敗しました。"
            exit 1
        fi
        echo "ブランチを削除しました。"
      else
        echo "Error: worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
        exit 1
      fi
    fi
    ;;
  *)
    # 移動モード (オプションなし)
    TARGET_BRANCH="$1"

    # BASE_BRANCH の場合、 cd で移動するのみを行う
    if [ "$TARGET_BRANCH" = "$BASE_BRANCH" ]; then
      exec "$SHELL" -c "cd \"${PARENT_DIR}/${BASE_REPO_NAME}\" && exec \"$SHELL\""
      echo "ディレクトリ ${PARENT_DIR}/${BASE_REPO_NAME} に移動しました。"
      exit 0
    fi

    WORKTREE_PATH="${PARENT_DIR}/${TARGET_BRANCH}_${BASE_REPO_NAME}"

    if [ ! -d "$WORKTREE_PATH" ]; then
      echo "Error: worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
      echo "${TARGET_BRANCH} ブランチのworktreeを作成するには './worktree.sh -b ${TARGET_BRANCH}' を使用してください。"
      exit 1
    fi

    # worktreeディレクトリに移動
    echo "${WORKTREE_PATH} に移動します..."
    exec "$SHELL" -c "cd \"$WORKTREE_PATH\" && exec \"$SHELL\""
    echo "ディレクトリ ${WORKTREE_PATH} に移動しました。"
esac
