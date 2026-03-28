
# ---- CONFIG ----
$GH_OWNER="exajoin"
$GH_REPO="ep"
$BASE_URL="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents"

function Read-Secret($msg) {
    $s = Read-Host $msg -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
}

# ---- AUTH ----
$env:GITHUB_TOKEN = Read-Secret "GitHub Token"

$headers = @{
    Authorization = "token $env:GITHUB_TOKEN"
}

# ---- OPTIONAL TOKENS ----
$env:AZDO_PAT = Read-Secret "AZDO PAT"
$env:TF_TOKEN = Read-Secret "Terraform Token"
$env:AWS_ACCESS_KEY_ID = Read-Secret "AWS Access Key"
$env:AWS_SECRET_ACCESS_KEY = Read-Secret "AWS Secret Key"

# ---- WORKSPACE ----
$env:USEP_WORKSPACE = Read-Host "Workspace name"

# ---- FETCH ----
function _fetch_file($path) {
    $resp = Invoke-RestMethod -Uri "$BASE_URL/$path" -Headers $headers
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($resp.content))
}

# ---- CREATE WORKSPACE ----
function _create_workspace {
    $path = "backlog/$env:USEP_WORKSPACE/.init"
    $body = @{
        message = "init workspace"
        content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("init"))
    } | ConvertTo-Json

    Invoke-RestMethod -Method Put -Uri "$BASE_URL/$path" -Headers $headers -Body $body -ErrorAction SilentlyContinue
}

_create_workspace

# ---- DISPATCH ----
function _usep($domain, $cmd, $arg) {
    switch ($domain) {
        "azdo" { _fetch_file "script/azdo.ps1" | Invoke-Expression }
        "tfdo" { _fetch_file "script/tfdo.ps1" | Invoke-Expression }
        "awdo" { _fetch_file "script/awdo.ps1" | Invoke-Expression }
        "run"  { _fetch_file "toolkit/$cmd.ps1" | Invoke-Expression }
        "exit" { _usep_exit }
        default { "Unknown domain" }
    }
}

# ---- HISTORY ----
function _usep_upload_history {
    $hist = Get-History | Out-String
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($hist))

    $body = @{
        message = "history upload"
        content = $encoded
    } | ConvertTo-Json

    Invoke-RestMethod -Method Put `
        -Uri "$BASE_URL/backlog/$env:USEP_WORKSPACE/history_$(Get-Date -UFormat %s).log" `
        -Headers $headers -Body $body
}

# ---- CLEANUP ----
function _usep_cleanup {
    Remove-Item Env:AZDO_PAT,Env:TF_TOKEN,Env:AWS_ACCESS_KEY_ID,Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
    Remove-Item function:_usep,function:_fetch_file,function:_usep_exit,function:_usep_cleanup -ErrorAction SilentlyContinue
}

function _usep_exit {
    _usep_upload_history
    _usep_cleanup
    "Session terminated"
}

"✅ USEP session initialized"
