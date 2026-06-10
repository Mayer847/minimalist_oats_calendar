param(
  [string]$Message = "Update app",
  [string]$Version = "patch",
  [string]$Branch = "main"
)

$insideRepo = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "Not inside a git repository."; exit 1 }

$currentTag = git tag --sort=-v:refname | Select-String -Pattern '^v[0-9]+\.[0-9]+\.[0-9]+$' | Select-Object -First 1
if ($null -eq $currentTag) { $currentTag = "v0.0.0" } else { $currentTag = $currentTag.ToString() }

function Bump-Version($tag, $part) {
  if ($part.StartsWith("v")) { return $part }
  $raw = $tag.TrimStart("v")
  $pieces = $raw.Split(".")
  [int]$major = $pieces[0]; [int]$minor = $pieces[1]; [int]$patch = $pieces[2]
  switch ($part) {
    "major" { $major++; $minor = 0; $patch = 0 }
    "minor" { $minor++; $patch = 0 }
    "patch" { $patch++ }
    default { Write-Error "Invalid version arg: $part. Use patch/minor/major or vX.Y.Z"; exit 1 }
  }
  return "v$major.$minor.$patch"
}

$newTag = Bump-Version $currentTag $Version
Write-Host "Current tag: $currentTag"
Write-Host "New tag:     $newTag"
Write-Host "Branch:      $Branch"

git status --short
git add .
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host "No staged changes to commit." } else { git commit -m $Message }

git rev-parse $newTag 2>$null
if ($LASTEXITCODE -eq 0) { Write-Host "Tag $newTag already exists. Skipping tag creation." } else { git tag -a $newTag -m "Release $newTag" }

git push origin $Branch
git push origin $newTag
Write-Host "Done. Pushed commit and tag $newTag."
