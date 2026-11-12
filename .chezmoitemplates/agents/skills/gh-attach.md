---
name: gh-attach
description: Attach images and videos (screenshots, recordings) to GitHub issues, PRs and comments directly from GitHub CLI with `--attach`, instead of asking the user to drag and drop them in the browser. Use whenever an issue, PR body or comment should include a screenshot, image, GIF or video, before telling the user to paste or upload a file by hand, and when the user says things like "attach this screenshot to the PR", "add the image to the issue", "post the recording as a comment", 「スクショをPRに貼って」「画像をissueに添付して」「動画をコメントに付けて」, or any similar phrasing in English or Japanese.
---

# gh-attach

GitHub CLI uploads images and videos itself, so never tell the user to paste a file into the browser by hand. Pass the file with `--attach` on the command that writes the body.

## Supported commands

| Command | Where the attachment goes |
| --- | --- |
| `gh issue create`, `gh pr create` | Appended to the body. Still pass `--title` and `--body` / `--body-file` (or `--fill` for a PR), since gh prompts for missing ones |
| `gh issue edit`, `gh pr edit` | Appended to the body; without a body flag the existing body is kept |
| `gh issue comment`, `gh pr comment` | Appended to the comment; `--attach` alone posts a comment with just the attachment |

Not supported: `gh pr review`, inline review comments, `gh release create`, `gh api`. For those, post the image with `gh pr comment --attach` and reference that comment, or tell the user the image needs to be added by hand.

If `gh issue comment --help` has no `--attach`, the installed gh is too old; tell the user to update it.

## Usage

```sh
# Appended to the end of the body / comment, alt text after '#'
gh issue comment 12 --attach './login.png#The login error state'

# Several files: repeat the flag (up to 50, the same file only once)
gh pr comment 34 --attach ./before.png --attach ./after.png
```

To place an image inside the text, reference the local path in the body and attach the same file. gh rewrites the reference to the uploaded URL and keeps the alt text written in the body:

```markdown
Before:

![sign-in form before the fix](./before.png)
```

```sh
gh pr create --title "..." --body-file body.md --attach ./before.png
```

- Paths in a `--body-file` resolve relative to that file's directory, then the working directory. Prefer absolute paths when the body file lives in a temp directory.
- Rewriting works for `--body`, `--body-file`, stdin and the editor alike.
- Attached files not referenced in the body are appended at the end, in flag order.
- A video renders as a player only when `![](./demo.mp4)` is alone in its paragraph; inline it becomes a link. Videos take no alt text.

## Constraints

- Images and videos only. Logs, PDFs and archives cannot be attached; paste text into a code block or link elsewhere.
- Requires push access to the repository.
- In a public repository, anyone with the uploaded URL can open the file without signing in; in a private one, anyone with access to the repository. Check that a screenshot shows no secrets, tokens or personal data, and confirm with the user before posting as with any other comment.
- If some uploads fail, gh still creates or edits the issue / PR with the ones that succeeded, prints its URL and exits non-zero. Do not rerun the create command. Add the missing files with `gh issue edit` / `gh pr edit --attach` on the printed URL.
