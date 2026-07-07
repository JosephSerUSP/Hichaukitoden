$tmp = New-TemporaryFile
& "C:\Program Files\LOVE\lovec.exe" . validate golden | Out-File -Encoding utf8 $tmp
$diff = Compare-Object (Get-Content tools/golden/battle.log) (Get-Content $tmp)
Remove-Item $tmp
if ($diff) {
    $diff
    exit 1
}
exit 0
