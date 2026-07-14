# Tube MP3 Tools

PowerShell helpers for cleaning ffmpeg-downloaded MP3 filenames and sorting/splitting mixes.

## Scripts

- `_Rename.ps1` renames root-folder MP3s to `Artist - Title.mp3`.
- `_Find-Singles.ps1` moves small/single-track MP3s to `SINGLES`.
- `_Split-Playlists.ps1` splits playlist/mix MP3s into numbered tracks in `SPLIT` and moves originals to `PLAYLISTS`.

## Usage

Run from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\_Rename.ps1
powershell -ExecutionPolicy Bypass -File .\_Rename.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\_Find-Singles.ps1
powershell -ExecutionPolicy Bypass -File .\_Split-Playlists.ps1
```

Single-file split:

```powershell
powershell -ExecutionPolicy Bypass -File .\_Split-Playlists.ps1 -FilePath "C:\path\to\file.mp3"
```

Requires `ffmpeg` and `ffprobe` in `PATH`.
