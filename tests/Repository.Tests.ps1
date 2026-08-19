$RepoRoot = Split-Path -Parent $PSScriptRoot

Describe 'Repository foundation' {
    It 'contains required public entry points' {
        @('README.md', 'LICENSE', '.gitignore', 'SECURITY.md', 'assets/architecture.svg') |
            ForEach-Object { Test-Path (Join-Path $RepoRoot $_) | Should -BeTrue }
    }

    It 'does not call the mounted architecture bisync' {
        $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
        $readme | Should -Match 'not.*bisync|not `rclone bisync`'
    }

    It 'states reference latency is not a guarantee' {
        $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
        $readme | Should -Match 'not.*guarantee|not.*SLA|configuration target'
    }

    It 'ignores sensitive rclone/runtime artifacts' {
        $ignore = Get-Content (Join-Path $RepoRoot '.gitignore') -Raw
        foreach ($pattern in @('rclone.conf', '*.token', '*.log', 'cache/', 'secrets/', '.env')) {
            $ignore | Should -Match ([regex]::Escape($pattern))
        }
    }
}

Describe 'Install-RcloneService.ps1' {
    $scriptPath = Join-Path $RepoRoot 'scripts/Install-RcloneService.ps1'

    It 'parses as valid PowerShell' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It 'declares required public parameters' {
        $command = Get-Command $scriptPath
        foreach ($name in @('RemoteName','DriveLetter','RcloneExe','ConfigPath','CacheDirectory','CacheMaxSize','CacheMaxAge','WriteBack','PollInterval','VolumeName','ServiceName','LogDirectory')) {
            $command.Parameters.Keys | Should -Contain $name
        }
    }

    It 'supports WhatIf' {
        (Get-Command $scriptPath).Parameters.Keys | Should -Contain 'WhatIf'
    }
}

Describe 'Start-RcloneAfterNetwork.ps1' {
    $scriptPath = Join-Path $RepoRoot 'scripts/Start-RcloneAfterNetwork.ps1'

    It 'parses as valid PowerShell' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It 'has a finite timeout parameter' {
        $command = Get-Command $scriptPath
        $command.Parameters.Keys | Should -Contain 'TimeoutSeconds'
    }

    It 'supports an optional mount path barrier' {
        (Get-Command $scriptPath).Parameters.Keys | Should -Contain 'MountPath'
    }
}

Describe 'Security hardening scripts' {
    foreach ($relative in @('scripts/Set-RcloneMountAcl.ps1','scripts/Protect-RcloneConfig.ps1')) {
        It "$relative parses as valid PowerShell" {
            $path = Join-Path $RepoRoot $relative
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }
    }

    It 'mount ACL script supports WhatIf' {
        (Get-Command (Join-Path $RepoRoot 'scripts/Set-RcloneMountAcl.ps1')).Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'config protection script never contains a command that prints rclone.conf contents' {
        $text = Get-Content (Join-Path $RepoRoot 'scripts/Protect-RcloneConfig.ps1') -Raw
        $text | Should -Not -Match 'Get-Content\s+.*rclone\.conf'
    }
}

Describe 'Verification and removal scripts' {
    It 'mount test declares DriveLetter and ServiceName' {
        $cmd = Get-Command (Join-Path $RepoRoot 'scripts/Test-RcloneMount.ps1')
        $cmd.Parameters.Keys | Should -Contain 'DriveLetter'
        $cmd.Parameters.Keys | Should -Contain 'ServiceName'
    }

    It 'removal script supports WhatIf' {
        (Get-Command (Join-Path $RepoRoot 'scripts/Remove-RcloneService.ps1')).Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'removal script does not delete config or cache by default' {
        $text = Get-Content (Join-Path $RepoRoot 'scripts/Remove-RcloneService.ps1') -Raw
        $text | Should -Match 'RemoveConfig'
        $text | Should -Match 'RemoveCache'
    }
}

Describe 'Replication documentation' {
    It 'README links to setup guide' {
        (Get-Content (Join-Path $RepoRoot 'README.md') -Raw) | Should -Match 'docs/SETUP\.md'
    }

    It 'setup guide uses sanitized placeholders' {
        $text = Get-Content (Join-Path $RepoRoot 'docs/SETUP.md') -Raw
        foreach ($placeholder in @('<WINDOWS_USER>','<RCLONE_REMOTE>','<DRIVE_LETTER>','<CONFIG_PATH>','<CACHE_DIR>')) {
            $text | Should -Match ([regex]::Escape($placeholder))
        }
    }
}

Describe 'Technical documentation coverage' {
    It 'migration guide emphasizes copy before verify before cleanup' {
        $text = Get-Content (Join-Path $RepoRoot 'docs/MIGRATION.md') -Raw
        $text | Should -Match 'rclone copy'
        $text | Should -Match 'rclone check'
        $text | Should -Match 'size-only'
        $text | Should -Match 'Personal Vault'
        $text | Should -Match 'disable ListR'
    }

    It 'troubleshooting documents the known failure modes' {
        $text = Get-Content (Join-Path $RepoRoot 'docs/TROUBLESHOOTING.md') -Raw
        foreach ($phrase in @('Location is not available','no such host','desktop.ini','Access denied','invalidResourceId','No common hash found')) {
            $text | Should -Match ([regex]::Escape($phrase))
        }
    }

    It 'Known Folders guide contains rollback guidance' {
        (Get-Content (Join-Path $RepoRoot 'docs/KNOWN-FOLDERS.md') -Raw) | Should -Match 'rollback|restore.*local'
    }
}

Describe 'Release safety' {
    $publicFiles = Get-ChildItem $RepoRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/]\.git[\\/]' -and
            $_.FullName -notmatch '[\\/]\.worktrees[\\/]' -and
            ($_.Extension -in @('.md','.ps1','.txt','.svg') -or $_.Name -eq '.gitignore')
        }

    It 'contains no obvious OAuth/token/config secrets' {
        $allText = ($publicFiles | ForEach-Object { Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue }) -join "`n"
        $allText | Should -Not -Match 'refresh_token\s*[:=]\s*[A-Za-z0-9_-]{20,}'
        $allText | Should -Not -Match 'access_token\s*[:=]\s*[A-Za-z0-9_-]{20,}'
        $allText | Should -Not -Match '\[gdrive\][\s\S]*token\s*=' 
    }

    It 'contains no reference-machine identifiers' {
        $allText = ($publicFiles | ForEach-Object { Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue }) -join "`n"
        $allText | Should -Not -Match 'C:\\Users\\[A-Za-z0-9._-]+\\AppData'
        $allText | Should -Not -Match 'S-1-5-21-[0-9-]+'
    }

    It 'does not track credential/runtime filenames' {
        $forbidden = @('rclone.conf','.env')
        foreach ($name in $forbidden) {
            @(Get-ChildItem $RepoRoot -Recurse -File -Filter $name | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]\.worktrees[\\/]' }).Count | Should -Be 0
        }
    }

    It 'parses every PowerShell script' {
        Get-ChildItem (Join-Path $RepoRoot 'scripts') -Filter '*.ps1' | ForEach-Object {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }
    }
}
