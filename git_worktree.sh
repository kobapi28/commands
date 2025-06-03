#!/bin/bash

###### 使用方法 ######
# ./worktree.sh <branchName> # 指定した名前のブランチに対応するworktreeに移動
# ./worktree.sh -b <branchName> # 指定した名前でブランチを作成、また {branchName}-{repoName} の形式でworktreeディレクトリを作成し移動
# ./worktree.sh -r <branchName> # 指定した名前のブランチを削除、また {branchName}-{repoName} の形式でworktreeディレクトリを削除
#####################

# 現在のGitリポジトリのルートディレクトリを取得
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
BASE_BRANCH=main
# worktree ディレクトリかどうかを判定
if [ "$(git rev-parse --git-dir)" = ".git" ]; then
  IS_WORKTREE=false
else
  IS_WORKTREE=true
fi

if [ -z "$REPO_ROOT" ]; then
  echo "エラー: Gitリポジトリではありません。"
  exit 1
fi

# スクリプトのディレクトリ
SCRIPT_DIR=$(dirname "$0")

# リポジトリの親ディレクトリ
PARENT_DIR=$(dirname "$REPO_ROOT")

# サブコマンドの処理
case "$1" in
  "-b")
    # 作成モード
    TARGET_BRANCH="$2"
    # {branchName}-{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_PATH="${PARENT_DIR}/${TARGET_BRANCH}-${REPO_NAME}"

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
    WORKTREE_PATH="${PARENT_DIR}/${REPO_NAME}"

    if [ -d "$WORKTREE_PATH" ]; then
      # FIXME: ここが WORKTREE_PATH を消すわけではない。消すのは {TARGET_BRANCH}-{REPO_NAME} のディレクトリ
      echo "worktreeディレクトリ ${WORKTREE_PATH} とブランチ ${TARGET_BRANCH} を削除します..."
      # REPO_NAME の最初の - までの文字列と受け取った TARGET_BRANCH が一致している場合は、元となるディレクトリに移動してから実行する
      REPO_NAME_PREFIX="${REPO_NAME%%-*}"
      REPO_NAME_SUFFIX="${REPO_NAME#*-}"

      if [ "${REPO_NAME_PREFIX}" = "${TARGET_BRANCH}" ]; then
        echo "このディレクトリが削除されるため移動します..."
        exec "$SHELL" -c "cd \"$WORKTREE_PATH\" && exec \"$SHELL\""
      fi
      git worktree remove "$REPO_NAME"
      if [ $? -ne 0 ]; then
        echo "Error: worktreeディレクトリの削除に失敗しました。"
        exit 1
      else
        echo "worktreeディレクトリを削除しました。"
      fi
    else
      echo "Error: worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
    fi

    # ブランチを削除
    git branch -d "$TARGET_BRANCH"
    if [ $? -ne 0 ]; then
        echo "Error: ブランチ ${TARGET_BRANCH} の削除に失敗しました。"
        exit 1
    fi
    echo "ブランチを削除しました。"
    ;;
  *)
    # 移動モード (オプションなし)
    TARGET_BRANCH="$1"
    WORKTREE_PATH="${PARENT_DIR}/${TARGET_BRANCH}-${REPO_NAME}"

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
