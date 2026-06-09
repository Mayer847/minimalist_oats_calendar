# Minimalist OATS Calendar v3

Flutter Web weekly schedule app inspired by the OATS weekly report sheet.

## v3 updates

- Local-first storage using browser local storage.
- Export/import full backup as JSON anytime.
- Download the visible schedule as PNG.
- GitHub Pages deployment workflow included.
- Start day selector moved to the top bar next to the 24h/12h control.
- Undo button for edits, imports, row changes, review changes, and drag/drop.
- Overlap handling: later items are pushed down automatically.
- Review any day from the `Review Day` button or by tapping a day header.
- Review screen has visible `Done`, `Missed`, and `Not sure` buttons directly.
- 30-minute slots with duration-based item blocks.
- Dashed row guides instead of full horizontal row borders.
- Long-press and drag:
  - Same day = move vertically.
  - Different day = copy horizontally.

## Run locally

```bash
flutter pub get
flutter run -d chrome
```

## Deploy to GitHub Pages today

1. Push this project to your repo.
2. In GitHub: Settings → Pages → Source → GitHub Actions.
3. Push to `main`.
4. Wait for the Actions workflow to finish.

The workflow automatically uses `/` for `<username>.github.io` repos and `/<repo-name>/` for project pages.
