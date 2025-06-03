#!/bin/bash

###### 使用方法 ######
# ./worktree.sh <branchName> # 指定した名前でブランチを作成、また {branchName}-{repoName} の形式でworktreeディレクトリを作成し移動
# ./worktree.sh -r <branchName> # 指定した名前のブランチを削除、また {branchName}-{repoName} の形式でworktreeディレクトリを削除
#####################

# 現在のGitリポジトリのルートディレクトリを取得
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
# worktree ディレクトリかどうかを判定
if [ "$(git rev-parse --git-dir)" = ".git" ]; then
  IS_WORKTREE=true
else
  IS_WORKTREE=false
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
  "-r")
    # 削除モード
    if [ -z "$2" ]; then
      echo "使用方法: gitc -r <branchName>"
      exit 1
    fi
    TARGET_BRANCH="$2"
    WORKTREE_PATH="${PARENT_DIR}/${TARGET_BRANCH}-${REPO_NAME}"

    if [ -d "$WORKTREE_PATH" ]; then
      echo "worktreeディレクトリ ${WORKTREE_PATH} とブランチ ${TARGET_BRANCH} を削除します..."
      git worktree remove "$TARGET_BRANCH-${REPO_NAME}"
      echo "worktreeディレクトリを削除しました。"
    else
      echo "エラー: worktreeディレクトリ ${WORKTREE_PATH} が見つかりません。"
    fi

    # ブランチを削除
    git branch -d "$TARGET_BRANCH"
    echo "ブランチを削除しました。"
    ;;
  *)
    # 作成モード
    if [ -z "$1" ]; then
      echo "使用方法: gitc <branchName>"
      echo "削除する場合: gc -r <branchName>"
      exit 1
    fi
    TARGET_BRANCH="$1"
    # {branchName}-{repoName} の形式でworktreeディレクトリを作成
    WORKTREE_PATH="${PARENT_DIR}/${TARGET_BRANCH}-${REPO_NAME}"

    if [ -d "$WORKTREE_PATH" ]; then
      echo "Error: 既に ${WORKTREE_PATH} ディレクトリが存在します。"
      echo "既存のworktreeを削除するには 'gc -r ${TARGET_BRANCH}' を使用してください。"
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
      echo "エラー: worktreeの作成に失敗しました。"
      exit 1
    fi
    echo "worktreeを正常に作成しました。"
    echo "worktreeディレクトリ: ${WORKTREE_PATH}"

    # 該当ブランチへ移動
    exec "$SHELL" -c "cd \"$WORKTREE_PATH\" && exec \"$SHELL\""
    echo "ブランチ ${TARGET_BRANCH} に移動しました。"
esac
