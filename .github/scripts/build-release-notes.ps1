[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
  [string] $Tag,

  [Parameter(Mandatory)]
  [string] $OutputPath,

  [string] $Repository = $env:GITHUB_REPOSITORY,

  [switch] $Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

class ReleaseNotesBuilder {
  hidden [string] $Tag
  hidden [string] $OutputPath
  hidden [string] $Repository
  hidden [bool] $Offline
  hidden [string] $TargetCommit
  hidden [string] $PreviousTag
  hidden [string] $Range
  hidden [string] $RepositoryUrl

  ReleaseNotesBuilder(
    [string] $tag,
    [string] $outputPath,
    [string] $repository,
    [bool] $offline
  ) {
    $this.Tag = $tag
    $this.OutputPath = $outputPath
    $this.Repository = $repository
    $this.Offline = $offline
  }

  [void] Build() {
    if ([string]::IsNullOrWhiteSpace($this.Repository)) {
      throw 'Repository must be provided or available through GITHUB_REPOSITORY.'
    }
    if ($this.Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
      throw "Invalid GitHub repository: $($this.Repository)"
    }

    $this.RepositoryUrl = "https://github.com/$($this.Repository)"
    $this.TargetCommit = $this.GitScalar(@('rev-parse', "$($this.Tag)^{commit}"))
    $this.PreviousTag = $this.FindPreviousTag()
    $this.Range = if ($this.PreviousTag) {
      "$($this.PreviousTag)..$($this.Tag)"
    } else {
      $this.Tag
    }

    $commits = @($this.ReadCommits(@()))
    $firstParentCommits = @($this.ReadCommits(@('--first-parent')))
    $mergeCommits = @($this.ReadCommits(@('--merges')))
    $generatedNotes = if ($this.Offline) {
      '_GitHub pull request and contributor summary is available in CI._'
    } else {
      $this.GenerateGitHubNotes()
    }

    $content = [System.Collections.Generic.List[string]]::new()
    $version = $this.Tag.Substring(1)
    $content.Add("# Flucord $version")
    $content.Add('')
    $content.Add('This release description was assembled automatically from the tagged Git history and GitHub change metadata.')
    $content.Add('')
    $content.Add('## GitHub change summary')
    $content.Add('')
    $content.Add($generatedNotes.Trim())
    $content.Add('')
    $content.Add('## Release scope')
    $content.Add('')
    $content.Add("- Tag: ``$($this.Tag)``")
    $content.Add("- Commit: [``$($this.TargetCommit.Substring(0, 12))``]($($this.RepositoryUrl)/commit/$($this.TargetCommit))")
    $content.Add("- Commits in range: $($commits.Count)")
    $content.Add("- First-parent commits: $($firstParentCommits.Count)")
    $content.Add("- Merge commits: $($mergeCommits.Count)")
    if ($this.PreviousTag) {
      $content.Add("- Comparison: [$($this.PreviousTag)...$($this.Tag)]($($this.RepositoryUrl)/compare/$($this.PreviousTag)...$($this.Tag))")
    } else {
      $content.Add("- History: [all commits through $($this.Tag)]($($this.RepositoryUrl)/commits/$($this.Tag))")
    }
    $content.Add('')

    $this.AppendConventionalIndex($content, $commits)
    $this.AppendCommitSection($content, 'Merge history', $mergeCommits)
    $this.AppendCommitSection($content, 'First-parent history', $firstParentCommits)

    $content.Add('<details>')
    $content.Add("<summary>Complete commit history ($($commits.Count) commits)</summary>")
    $content.Add('')
    $this.AppendCommitList($content, $commits)
    $content.Add('')
    $content.Add('</details>')
    $content.Add('')
    $content.Add('## Build provenance')
    $content.Add('')
    $content.Add('- Built by GitHub Actions on the pinned tag commit.')
    $content.Add('- Flutter 3.44.7 and Dart 3.12.2 from the checksum-verified official Flutter archive.')
    $content.Add('- Gates: complete repository privacy audit, `flutter analyze`, full `flutter test`, and Windows release compilation.')
    $content.Add('- Distribution: complete Windows x64 runtime directory plus `SHA256SUMS.txt`.')
    $content.Add('')
    $content.Add('Flucord is experimental and is not affiliated with Discord. The desktop-user transport relies on a private protocol that can change without notice.')

    $parent = Split-Path -Parent $this.OutputPath
    if ($parent) {
      [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
      $this.OutputPath,
      ($content -join "`n") + "`n",
      $utf8
    )
    Write-Host "Generated release notes with $($commits.Count) commit(s): $($this.OutputPath)"
  }

  hidden [string] FindPreviousTag() {
    $candidates = @(& git tag --merged "$($this.Tag)^" --sort=-version:refname)
    if ($LASTEXITCODE -ne 0) {
      throw 'Unable to enumerate previous tags.'
    }
    foreach ($candidate in $candidates) {
      if ($candidate -match '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        return $candidate
      }
    }
    return ''
  }

  hidden [object[]] ReadCommits([string[]] $extraArguments) {
    $arguments = @('log') + $extraArguments + @(
      '--format=%H%x09%s',
      $this.Range
    )
    $lines = @(& git @arguments)
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to read Git history for $($this.Range)."
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
      $parts = $line -split "`t", 2
      if ($parts.Count -eq 2) {
        $result.Add([pscustomobject]@{
          Hash = $parts[0]
          Subject = $parts[1]
        })
      }
    }
    return $result.ToArray()
  }

  hidden [string] GenerateGitHubNotes() {
    $arguments = @(
      'api', '--method', 'POST',
      "repos/$($this.Repository)/releases/generate-notes",
      '-f', "tag_name=$($this.Tag)",
      '-f', "target_commitish=$($this.TargetCommit)"
    )
    if ($this.PreviousTag) {
      $arguments += @('-f', "previous_tag_name=$($this.PreviousTag)")
    }
    $json = @(& gh @arguments) -join "`n"
    if ($LASTEXITCODE -ne 0) {
      throw 'GitHub failed to generate pull request and contributor notes.'
    }
    $response = $json | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string] $response.body)) {
      return '_No pull requests were associated with this release range._'
    }
    return [string] $response.body
  }

  hidden [void] AppendConventionalIndex(
    [System.Collections.Generic.List[string]] $content,
    [object[]] $commits
  ) {
    $groups = [ordered]@{
      'Features' = [System.Collections.Generic.List[object]]::new()
      'Fixes' = [System.Collections.Generic.List[object]]::new()
      'Documentation' = [System.Collections.Generic.List[object]]::new()
      'Build, tests, and maintenance' = [System.Collections.Generic.List[object]]::new()
      'Other changes' = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($commit in $commits) {
      $group = switch -Regex ($commit.Subject) {
        '^feat(?:\(.+\))?!?:' { 'Features'; break }
        '^fix(?:\(.+\))?!?:' { 'Fixes'; break }
        '^docs?(?:\(.+\))?!?:' { 'Documentation'; break }
        '^(?:build|chore|ci|perf|refactor|revert|style|test)(?:\(.+\))?!?:' {
          'Build, tests, and maintenance'; break
        }
        default { 'Other changes' }
      }
      $groups[$group].Add($commit)
    }

    $content.Add('## Changes by type')
    $content.Add('')
    foreach ($entry in $groups.GetEnumerator()) {
      if ($entry.Value.Count -eq 0) {
        continue
      }
      $content.Add("### $($entry.Key)")
      $content.Add('')
      $this.AppendCommitList($content, $entry.Value.ToArray())
      $content.Add('')
    }
  }

  hidden [void] AppendCommitSection(
    [System.Collections.Generic.List[string]] $content,
    [string] $title,
    [object[]] $commits
  ) {
    $content.Add("## $title")
    $content.Add('')
    if ($commits.Count -eq 0) {
      $content.Add('_No commits in this category._')
    } else {
      $this.AppendCommitList($content, $commits)
    }
    $content.Add('')
  }

  hidden [void] AppendCommitList(
    [System.Collections.Generic.List[string]] $content,
    [object[]] $commits
  ) {
    foreach ($commit in $commits) {
      $shortHash = $commit.Hash.Substring(0, 8)
      $subject = $this.EscapeMarkdown([string] $commit.Subject)
      $content.Add("- [``$shortHash``]($($this.RepositoryUrl)/commit/$($commit.Hash)) $subject")
    }
  }

  hidden [string] EscapeMarkdown([string] $value) {
    return $value.Replace('\', '\\').Replace('[', '\[').Replace(']', '\]')
  }

  hidden [string] GitScalar([string[]] $arguments) {
    $value = @(& git @arguments) -join ''
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
      throw "git $($arguments -join ' ') did not return a value."
    }
    return $value.Trim()
  }
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$builder = [ReleaseNotesBuilder]::new($Tag, $resolvedOutput, $Repository, $Offline)
$builder.Build()
