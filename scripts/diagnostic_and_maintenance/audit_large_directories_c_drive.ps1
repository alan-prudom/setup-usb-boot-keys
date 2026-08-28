$ErrorActionPreference = 'SilentlyContinue'

"=== Top-Level Directories on C:\ ==="
Get-ChildItem -Path C:\ -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            Folder = $_.FullName
            Size_GB = [math]::Round($size / 1GB, 2)
        }
    }
} | Sort-Object Size_GB -Descending | Format-Table -AutoSize

"=== Large User Folders in C:\Users ==="
Get-ChildItem -Path C:\Users -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            UserFolder = $_.FullName
            Size_GB = [math]::Round($size / 1GB, 2)
        }
    }
} | Sort-Object Size_GB -Descending | Format-Table -AutoSize
