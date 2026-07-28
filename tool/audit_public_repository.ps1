[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

class AuditFinding {
  AuditFinding([string] $category, [string] $location) {
    $this.Category = $category
    $this.Location = $location
  }

  [string] $Category
  [string] $Location
}

class RepositoryPrivacyAudit {
  hidden [string] $Root
  hidden [System.Collections.Generic.List[AuditFinding]] $Findings
  hidden [System.Collections.Generic.HashSet[string]] $FindingKeys
  hidden [System.Collections.Generic.HashSet[string]] $AllowedSnowflakes
  hidden [System.Text.RegularExpressions.Regex] $EmailPattern
  hidden [System.Text.RegularExpressions.Regex] $IpPattern
  hidden [System.Text.RegularExpressions.Regex] $SnowflakePattern
  hidden [object[]] $ContentRules

  RepositoryPrivacyAudit([string] $root) {
    $this.Root = $root
    $this.Findings = [System.Collections.Generic.List[AuditFinding]]::new()
    $this.FindingKeys = [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    $this.AllowedSnowflakes = [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::Ordinal
    )
    # Values no account, guild or channel can be behind: a repeated digit, a
    # run of consecutive ones, or a one followed by nothing but zeroes. Test
    # fixtures reach for these, and history keeps them forever, so they are
    # named here rather than treated as a leak.
    foreach ($value in @(
      '100000000000000000',
      '111111111111111111',
      '123456789012345678',
      '200000000000000000',
      '222222222222222222',
      '234567890123456789',
      '300000000000000000',
      '333333333333333333',
      '987654321098765432'
    )) {
      [void] $this.AllowedSnowflakes.Add($value)
    }

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $this.EmailPattern = [regex]::new(
      '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
      $options
    )
    $this.IpPattern = [regex]::new(
      '(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])'
    )
    $this.SnowflakePattern = [regex]::new(
      '(?<![0-9A-Fa-f])[0-9]{17,20}(?![0-9A-Fa-f])'
    )

    $privateKey = 'BEGIN\s+(?:(?:RSA|EC|OPENSSH|DSA)\s+)?' +
      'PRIVATE\s+KEY'
    $githubToken = '(?:github' + '_pat_|gh[pousr]_)[A-Z0-9_]{20,}'
    $discordToken = '(?:mfa\.[A-Z0-9_-]{20,}|' +
      '[A-Z0-9_-]{24}\.[A-Z0-9_-]{6}\.[A-Z0-9_-]{20,})'
    $awsKey = 'AKIA[0-9A-Z]{16}'
    $userPath = '(?:(?i:[A-Z]:\\' + 'Users\\[^\\\s]+)|' +
      '/Users/[^/\s]+|/home/[^/\s]+/(?:Desktop|Documents|Downloads|code|src)/)'
    $credential = '(?:authorization|password|secret|token)\s*[:=]\s*' +
      '[''\"][A-Z0-9_./+=:-]{20,}[''\"]'

    $this.ContentRules = @(
      [pscustomobject]@{ Category = 'private-key'; Pattern = [regex]::new($privateKey, $options) },
      [pscustomobject]@{ Category = 'github-token'; Pattern = [regex]::new($githubToken, $options) },
      [pscustomobject]@{ Category = 'discord-token'; Pattern = [regex]::new($discordToken, $options) },
      [pscustomobject]@{ Category = 'aws-access-key'; Pattern = [regex]::new($awsKey) },
      [pscustomobject]@{ Category = 'local-user-path'; Pattern = [regex]::new($userPath) },
      [pscustomobject]@{ Category = 'literal-credential'; Pattern = [regex]::new($credential, $options) }
    )
  }

  [int] Run() {
    $this.AssertRepository()
    $commits = @($this.InvokeGit(@('rev-list', '--all')))
    $this.ScanCommitMetadata($commits)
    $this.ScanTagMetadata()
    $this.ScanHistoricalPaths()
    $this.ScanHistoricalContent($commits)
    $this.ScanImageMetadata()

    if ($this.Findings.Count -gt 0) {
      Write-Host "Repository privacy audit failed with $($this.Findings.Count) finding(s):"
      foreach ($finding in $this.Findings) {
        Write-Host "  $($finding.Category): $($finding.Location)"
      }
      Write-Host 'Matched values are intentionally omitted.'
      return 1
    }

    Write-Host "Repository privacy audit passed across $($commits.Count) commit(s)."
    return 0
  }

  hidden [void] AssertRepository() {
    if (-not (Test-Path -LiteralPath (Join-Path $this.Root '.git'))) {
      throw "Not a Git repository: $($this.Root)"
    }
  }

  hidden [string[]] InvokeGit([string[]] $arguments) {
    Push-Location $this.Root
    try {
      $output = @(& git @arguments 2>$null)
      if ($LASTEXITCODE -ne 0) {
        throw "git $($arguments -join ' ') failed with exit code $LASTEXITCODE"
      }
      return [string[]] $output
    } finally {
      Pop-Location
    }
  }

  hidden [void] AddFinding([string] $category, [string] $location) {
    $key = "$category`n$location"
    if ($this.FindingKeys.Add($key)) {
      $this.Findings.Add([AuditFinding]::new($category, $location))
    }
  }

  hidden [void] ScanCommitMetadata([string[]] $commits) {
    foreach ($commit in $commits) {
      $metadata = @($this.InvokeGit(@(
        'show', '-s', '--format=%an%x09%ae%x09%B', $commit
      ))) -join "`n"
      $location = "commit $($commit.Substring(0, 12)) metadata"

      foreach ($email in $this.EmailPattern.Matches($metadata)) {
        if (-not $this.IsAllowedEmail($email.Value)) {
          $this.AddFinding('personal-email', $location)
        }
      }
      $this.InspectText($metadata, $location)
    }
  }

  hidden [void] ScanTagMetadata() {
    $tags = $this.InvokeGit(@('tag', '--list'))
    foreach ($tag in $tags) {
      $metadata = @($this.InvokeGit(@(
        'for-each-ref',
        '--format=%(taggername)%09%(taggeremail)%09%(contents)',
        "refs/tags/$tag"
      ))) -join "`n"
      $location = "tag $tag metadata"
      foreach ($email in $this.EmailPattern.Matches($metadata)) {
        if (-not $this.IsAllowedEmail($email.Value)) {
          $this.AddFinding('personal-email', $location)
        }
      }
      $this.InspectText($metadata, $location)
    }
  }

  hidden [void] ScanHistoricalPaths() {
    $paths = $this.InvokeGit(@('log', '--all', '--name-only', '--format=')) |
      Where-Object { $_ } |
      Sort-Object -Unique
    foreach ($path in $paths) {
      if ($path -match '(?i)(^|/)(\.env(?:\..*)?|credentials?\.json|secrets?\.json|id_(?:rsa|dsa|ecdsa|ed25519))$' -or
          $path -match '(?i)\.(?:pfx|p12|key|kdbx|sqlite3?|db|log)$') {
        if ($path -notmatch '(?i)(^|/)dsa_pub\.pem$') {
          $this.AddFinding('sensitive-path', "historical path $path")
        }
      }
      if ($path -match '(?i)(?:^[A-Z]:\\|^/(?:Users|home)/)') {
        $this.AddFinding('absolute-path', "historical path $path")
      }
    }
  }

  hidden [void] ScanHistoricalContent([string[]] $commits) {
    $broadPattern = @(
      'PRIVATE[[:space:]]+KEY',
      'github_pat_',
      'gh[pousr]_',
      'mfa\.',
      'AKIA[0-9A-Z]{16}',
      '[A-Za-z]:\\Users\\',
      '/(Users|home)/',
      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
      '([0-9]{1,3}\.){3}[0-9]{1,3}',
      '[0-9]{17,20}',
      '(authorization|password|secret|token)[[:space:]]*[:=]'
    ) -join '|'

    foreach ($commit in $commits) {
      Push-Location $this.Root
      try {
        $matches = @(& git grep -I -n -E $broadPattern $commit -- . 2>$null)
        if ($LASTEXITCODE -notin @(0, 1)) {
          throw "git grep failed for $commit with exit code $LASTEXITCODE"
        }
      } finally {
        Pop-Location
      }

      foreach ($match in $matches) {
        if ($match -notmatch '^[^:]+:(.*?):([0-9]+):(.*)$') {
          continue
        }
        $path = $Matches[1]
        $line = $Matches[2]
        $text = $Matches[3]
        $location = "$($commit.Substring(0, 12)):$path`:$line"
        $this.InspectText($text, $location)
      }
    }
  }

  hidden [void] InspectText([string] $text, [string] $location) {
    foreach ($rule in $this.ContentRules) {
      if ($rule.Pattern.IsMatch($text) -and
          -not $this.IsAllowedPlaceholder($text, $rule.Category, $location)) {
        $this.AddFinding($rule.Category, $location)
      }
    }

    foreach ($email in $this.EmailPattern.Matches($text)) {
      if (-not $this.IsAllowedEmail($email.Value)) {
        $this.AddFinding('personal-email', $location)
      }
    }
    foreach ($ip in $this.IpPattern.Matches($text)) {
      if (-not $this.IsAllowedIpAddress($ip.Value)) {
        $this.AddFinding('public-ip-address', $location)
      }
    }
    foreach ($snowflake in $this.SnowflakePattern.Matches($text)) {
      if (-not $this.AllowedSnowflakes.Contains($snowflake.Value)) {
        $this.AddFinding('discord-snowflake', $location)
      }
    }
  }

  hidden [bool] IsAllowedEmail([string] $email) {
    return $email -match '(?i)@(?:example\.(?:com|org|net)|[^@]+\.test|users\.noreply\.github\.com)$'
  }

  hidden [bool] IsAllowedIpAddress([string] $value) {
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($value, [ref] $address)) {
      return $true
    }
    $bytes = $address.GetAddressBytes()
    return $bytes[0] -eq 0 -or
      $bytes[0] -eq 10 -or
      $bytes[0] -eq 127 -or
      ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
      ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
      ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
      ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -eq 2) -or
      ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
      ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) -or
      $bytes[0] -ge 224
  }

  hidden [bool] IsAllowedPlaceholder(
    [string] $text,
    [string] $category,
    [string] $location
  ) {
    if ($category -eq 'local-user-path' -and
        $location -match ':tool/audit_public_repository\.ps1:[0-9]+$' -and
        ($text -match '^\s*\$userPath\s*=' -or
         $text -match '\[\^/\\s\]\+\|/home/')) {
      return $true
    }
    if ($category -ne 'literal-credential') {
      return $false
    }
    return $text -match '(?i)[''"](?:user|desktop|bot)-authorization[''"]' -or
      $text -match '(?i)[''"](?:request|captcha|refresh|access|sdk)-token[''"]' -or
      $text -match '(?i)[''"]captcha-request-token[''"]' -or
      $text -match '(?i)[''"](?:client|lobby|join)-secret[''"]'
  }

  hidden [void] ScanImageMetadata() {
    $imagePaths = $this.InvokeGit(@('ls-files', '*.png', '*.jpg', '*.jpeg'))
    foreach ($relativePath in $imagePaths) {
      $path = Join-Path $this.Root $relativePath
      if (-not (Test-Path -LiteralPath $path)) {
        continue
      }
      $bytes = [System.IO.File]::ReadAllBytes($path)
      $metadata = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
      foreach ($rule in $this.ContentRules) {
        if ($rule.Pattern.IsMatch($metadata)) {
          $this.AddFinding('image-metadata', $relativePath)
        }
      }
      foreach ($email in $this.EmailPattern.Matches($metadata)) {
        if (-not $this.IsAllowedEmail($email.Value)) {
          $this.AddFinding('image-metadata-email', $relativePath)
        }
      }
    }
  }
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$audit = [RepositoryPrivacyAudit]::new($repositoryRoot)
exit $audit.Run()
