param([string]$Message="Update app", [string]$Version="patch", [string]$Branch="main")
$currentTag = git tag --sort=-v:refname | Select-String -Pattern '^v[0-9]+\.[0-9]+\.[0-9]+$' | Select-Object -First 1
if ($null -eq $currentTag) { $currentTag = "v0.0.0" } else { $currentTag = $currentTag.ToString() }
function Bump-Version($tag,$part){ if($part.StartsWith("v")){return $part}; $p=$tag.TrimStart("v").Split("."); [int]$major=$p[0]; [int]$minor=$p[1]; [int]$patch=$p[2]; switch($part){"major"{$major++;$minor=0;$patch=0}"minor"{$minor++;$patch=0}"patch"{$patch++} default{Write-Error "Use patch/minor/major or vX.Y.Z"; exit 1}}; return "v$major.$minor.$patch" }
$newTag = Bump-Version $currentTag $Version
git add .
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { git commit -m $Message }
git rev-parse $newTag 2>$null
if ($LASTEXITCODE -ne 0) { git tag -a $newTag -m "Release $newTag" }
git push origin $Branch
git push origin $newTag
Write-Host "Pushed $newTag"
