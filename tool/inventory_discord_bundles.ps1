<#
.SYNOPSIS
  Builds a reproducible capability inventory of the installed Discord desktop
  client and its renderer bundles.

.DESCRIPTION
  The inventory is static analysis only. It reads the installed program
  directory and the publicly served renderer chunks. It never opens Discord's
  Local Storage, Session Storage, Cookies, Network cache, credential records,
  or any message content, and it never launches the client.

  Output is a deterministic JSON document plus an exit code that fails when the
  bundle exposes a capability segment or Gateway dispatch event that
  docs/DISCORD_BUNDLE_COVERAGE.md has not classified yet.
#>
[CmdletBinding()]
param(
  [string] $DiscordRoot = (Join-Path $env:LOCALAPPDATA 'Discord'),
  [string] $CacheDirectory = (Join-Path $env:TEMP 'flucord-discord-bundles'),
  [string] $OutputPath,
  [switch] $Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputPath) {
  $OutputPath = Join-Path $repositoryRoot 'docs/discord_bundle_inventory.json'
}

# Ledger identifiers. Every identifier must exist in DISCORD_BUNDLE_COVERAGE.md.
$script:Domains = @(
  'FBC-GATEWAY', 'FBC-ACCOUNT', 'FBC-PROFILE', 'FBC-PRESENCE',
  'FBC-RELATIONSHIPS', 'FBC-GUILD', 'FBC-CHANNEL', 'FBC-MESSAGE',
  'FBC-READSTATE', 'FBC-EXPRESSION', 'FBC-VOICE', 'FBC-STAGE', 'FBC-EVENTS',
  'FBC-APPLICATION', 'FBC-OAUTH', 'FBC-COMMERCE', 'FBC-MODERATION',
  'FBC-GAMES', 'FBC-AI', 'FBC-PLATFORM', 'FBC-NATIVE'
)

# First REST path segment -> ledger identifier.
$script:SegmentDomains = @{
  'users' = 'FBC-PROFILE'; 'settings' = 'FBC-PROFILE'
  'unique-username' = 'FBC-PROFILE'; 'badge-icons' = 'FBC-PROFILE'
  'guilds' = 'FBC-GUILD'; 'discovery' = 'FBC-GUILD'; 'roles' = 'FBC-GUILD'
  'discoverable-guilds' = 'FBC-GUILD'; 'guild-discovery' = 'FBC-GUILD'
  'join-requests' = 'FBC-GUILD'; 'member-verification' = 'FBC-GUILD'
  'member-verification-for-hub' = 'FBC-GUILD'; 'hub-waitlist' = 'FBC-GUILD'
  'template' = 'FBC-GUILD'; 'templates' = 'FBC-GUILD'
  'widget-configs' = 'FBC-GUILD'; 'community' = 'FBC-GUILD'
  'generated-pools' = 'FBC-GUILD'; 'gravity-content' = 'FBC-GUILD'
  'gravity-topic-guilds' = 'FBC-GUILD'
  'gravity-custom-guild-score' = 'FBC-GUILD'
  'gravity-recommended-guilds' = 'FBC-GUILD'
  'channels' = 'FBC-CHANNEL'; 'threads' = 'FBC-CHANNEL'
  'gravity-custom-channel-scores' = 'FBC-CHANNEL'
  'messages' = 'FBC-MESSAGE'; 'messages-log' = 'FBC-MESSAGE'
  'attachments' = 'FBC-MESSAGE'; 'unfurler' = 'FBC-MESSAGE'
  'read-states' = 'FBC-READSTATE'; 'icymi' = 'FBC-READSTATE'
  'disable-email-notifications' = 'FBC-READSTATE'
  'disable-server-highlight-notifications' = 'FBC-READSTATE'
  'emojis' = 'FBC-EXPRESSION'; 'stickers' = 'FBC-EXPRESSION'
  'sticker-packs' = 'FBC-EXPRESSION'; 'soundboard-sounds' = 'FBC-EXPRESSION'
  'soundboard-default-sounds' = 'FBC-EXPRESSION'; 'gifs' = 'FBC-EXPRESSION'
  'tenor' = 'FBC-EXPRESSION'; 'giphy' = 'FBC-EXPRESSION'
  'klipy' = 'FBC-EXPRESSION'
  'voice' = 'FBC-VOICE'; 'voice-hangouts' = 'FBC-VOICE'
  'conference-mode' = 'FBC-VOICE'; 'streams' = 'FBC-VOICE'
  'clips' = 'FBC-VOICE'; 'networking' = 'FBC-VOICE'
  'stage-instances' = 'FBC-STAGE'; 'guild-stages' = 'FBC-STAGE'
  'guild-events' = 'FBC-EVENTS'; 'events' = 'FBC-EVENTS'
  'applications' = 'FBC-APPLICATION'; 'apps' = 'FBC-APPLICATION'
  'applications-with-assets' = 'FBC-APPLICATION'
  'unverified-applications' = 'FBC-APPLICATION'
  'platform-application' = 'FBC-APPLICATION'
  'application-directory' = 'FBC-APPLICATION'
  'application-directory-static' = 'FBC-APPLICATION'
  'activities' = 'FBC-APPLICATION'; 'activity' = 'FBC-APPLICATION'
  'interactions' = 'FBC-APPLICATION'; 'developers' = 'FBC-APPLICATION'
  'teams' = 'FBC-APPLICATION'; 'branches' = 'FBC-APPLICATION'
  'build' = 'FBC-APPLICATION'; 'partners' = 'FBC-APPLICATION'
  'oauth2' = 'FBC-OAUTH'; 'connections' = 'FBC-OAUTH'; 'connect' = 'FBC-OAUTH'
  'integrations' = 'FBC-OAUTH'; 'webhooks' = 'FBC-OAUTH'
  'invite' = 'FBC-OAUTH'; 'invites' = 'FBC-OAUTH'
  'billing' = 'FBC-COMMERCE'; 'store' = 'FBC-COMMERCE'
  'storefront' = 'FBC-COMMERCE'; 'shop' = 'FBC-COMMERCE'
  'gifts' = 'FBC-COMMERCE'; 'entitlements' = 'FBC-COMMERCE'
  'subscription-plans' = 'FBC-COMMERCE'; 'quests' = 'FBC-COMMERCE'
  'quest-home' = 'FBC-COMMERCE'; 'quest-preview' = 'FBC-COMMERCE'
  'wishlist' = 'FBC-COMMERCE'; 'wishlists' = 'FBC-COMMERCE'
  'redeem' = 'FBC-COMMERCE'; 'referrals' = 'FBC-COMMERCE'
  'promotions' = 'FBC-COMMERCE'; 'bogo-promotions' = 'FBC-COMMERCE'
  'outbound-promotions' = 'FBC-COMMERCE'; 'premium-marketing' = 'FBC-COMMERCE'
  'user-offers' = 'FBC-COMMERCE'; 'user-offer-ids' = 'FBC-COMMERCE'
  'virtual-currency' = 'FBC-COMMERCE'; 'authorize-payment' = 'FBC-COMMERCE'
  'google-play' = 'FBC-COMMERCE'; 'layouts' = 'FBC-COMMERCE'
  'vibegrations' = 'FBC-COMMERCE'
  'collectibles-categories' = 'FBC-COMMERCE'
  'collectibles-products' = 'FBC-COMMERCE'
  'collectibles-shop-tab-layouts' = 'FBC-COMMERCE'
  'reporting' = 'FBC-MODERATION'; 'report' = 'FBC-MODERATION'
  'reports' = 'FBC-MODERATION'; 'report-review' = 'FBC-MODERATION'
  'mod-report' = 'FBC-MODERATION'; 'safety-hub' = 'FBC-MODERATION'
  'safety-flows' = 'FBC-MODERATION'; 'family-center' = 'FBC-MODERATION'
  'account-standing' = 'FBC-MODERATION'
  'games' = 'FBC-GAMES'; 'library' = 'FBC-GAMES'; 'haven' = 'FBC-GAMES'
  'consoles' = 'FBC-GAMES'; 'partner-sdk' = 'FBC-GAMES'
  'game-invite' = 'FBC-GAMES'
  'roblox-applications-supplemental-data' = 'FBC-GAMES'
  'friend-suggestions' = 'FBC-RELATIONSHIPS'
  'friend-finder' = 'FBC-RELATIONSHIPS'
  'message-requests' = 'FBC-RELATIONSHIPS'
  'auth' = 'FBC-ACCOUNT'; 'login' = 'FBC-ACCOUNT'; 'register' = 'FBC-ACCOUNT'
  'mfa' = 'FBC-ACCOUNT'; 'reject-mfa' = 'FBC-ACCOUNT'
  'sso' = 'FBC-ACCOUNT'; 'sso-token' = 'FBC-ACCOUNT'
  'activate' = 'FBC-ACCOUNT'; 'handoff' = 'FBC-ACCOUNT'
  'mweb-handoff' = 'FBC-ACCOUNT'; 'captcha' = 'FBC-ACCOUNT'
  'verify' = 'FBC-ACCOUNT'; 'verify-request' = 'FBC-ACCOUNT'
  'verify-hub-email' = 'FBC-ACCOUNT'; 'reset' = 'FBC-ACCOUNT'
  'wasntme' = 'FBC-ACCOUNT'; 'authorize-ip' = 'FBC-ACCOUNT'
  'reject-ip' = 'FBC-ACCOUNT'; 'age-verification' = 'FBC-ACCOUNT'
  'phone-verifications' = 'FBC-ACCOUNT'; 'download-qr-code' = 'FBC-ACCOUNT'
  'ai' = 'FBC-AI'
  'experiments' = 'FBC-PLATFORM'; 'apex' = 'FBC-PLATFORM'
  'science' = 'FBC-PLATFORM'; 'metrics' = 'FBC-PLATFORM'
  'debug' = 'FBC-PLATFORM'; 'debug-logs' = 'FBC-PLATFORM'
  'changelogs' = 'FBC-PLATFORM'; 'feature' = 'FBC-PLATFORM'
  'tutorial' = 'FBC-PLATFORM'; 'initiate-prompts' = 'FBC-PLATFORM'
  'content-inventory' = 'FBC-PLATFORM'; 'holidays' = 'FBC-PLATFORM'
  'snowsgiving' = 'FBC-PLATFORM'; 'app' = 'FBC-PLATFORM'
  'popout' = 'FBC-PLATFORM'; 'private' = 'FBC-PLATFORM'
  'domain-migration' = 'FBC-PLATFORM'; 'open-app-from-email' = 'FBC-PLATFORM'
}

# Ordered Gateway dispatch prefix rules. First match wins.
$script:EventRules = @(
  @('GUILD_SCHEDULED_EVENT', 'FBC-EVENTS'),
  @('GUILD_SOUNDBOARD', 'FBC-EXPRESSION'),
  @('GUILD_EMOJIS_', 'FBC-EXPRESSION'), @('GUILD_STICKERS_', 'FBC-EXPRESSION'),
  @('GUILD_BAN', 'FBC-MODERATION'), @('GUILD_BULK_BAN', 'FBC-MODERATION'),
  @('GUILD_PRUNE', 'FBC-MODERATION'),
  @('GUILD_INTEGRATIONS_', 'FBC-OAUTH'),
  @('GUILD_APPLICATION_COMMAND', 'FBC-APPLICATION'),
  @('GUILD_OFFICIAL_GAME_APPLICATIONS', 'FBC-GAMES'),
  @('GUILD_APPLIED_BOOSTS', 'FBC-COMMERCE'),
  @('GUILD_POWERUP_ENTITLEMENTS', 'FBC-COMMERCE'),
  @('GUILD_RING_', 'FBC-VOICE'), @('GUILD_ROOM_', 'FBC-VOICE'),
  @('GUILD_FEATURE_ACK', 'FBC-READSTATE'),
  @('GUILD_', 'FBC-GUILD'),
  @('CHANNEL_RECIPIENT', 'FBC-RELATIONSHIPS'),
  @('CHANNEL_', 'FBC-CHANNEL'), @('THREAD_', 'FBC-CHANNEL'),
  @('FORUM_UNREADS', 'FBC-READSTATE'),
  @('MESSAGE_REQUEST_', 'FBC-RELATIONSHIPS'),
  @('MESSAGE_', 'FBC-MESSAGE'), @('LAST_MESSAGES', 'FBC-MESSAGE'),
  @('SAVED_MESSAGE_', 'FBC-MESSAGE'),
  @('RECENT_MENTION_', 'FBC-READSTATE'),
  @('NOTIFICATION_CENTER_', 'FBC-READSTATE'),
  @('NOTIFICATION_SETTINGS_UPDATE', 'FBC-READSTATE'),
  @('GENERIC_PUSH_NOTIFICATION_SENT', 'FBC-READSTATE'),
  @('REACTION_NOTIFICATION_SENT', 'FBC-READSTATE'),
  @('DM_SETTINGS_UPSELL_SHOW', 'FBC-READSTATE'),
  @('RELATIONSHIP_', 'FBC-RELATIONSHIPS'),
  @('FRIEND_SUGGESTION_', 'FBC-RELATIONSHIPS'),
  @('GAME_RELATIONSHIP_', 'FBC-RELATIONSHIPS'),
  @('VOICE_', 'FBC-VOICE'), @('STREAM_', 'FBC-VOICE'),
  @('CALL_', 'FBC-VOICE'), @('CLIPS_', 'FBC-VOICE'),
  @('STAGE_INSTANCE_', 'FBC-STAGE'),
  @('PRESENCE', 'FBC-PRESENCE'), @('TYPING_START', 'FBC-PRESENCE'),
  @('ACTIVITY_', 'FBC-APPLICATION'),
  @('APPLICATION_COMMAND_', 'FBC-APPLICATION'),
  @('INTERACTION_', 'FBC-APPLICATION'),
  @('USER_APPLICATION_', 'FBC-APPLICATION'),
  @('CONSOLE_COMMAND_UPDATE', 'FBC-GAMES'),
  @('GAME_SERVER_', 'FBC-GAMES'), @('HAVEN_', 'FBC-GAMES'),
  @('LIBRARY_APPLICATION_UPDATE', 'FBC-GAMES'),
  @('SOCIAL_LAYER_SKU_', 'FBC-COMMERCE'),
  @('USER_CONNECTIONS_', 'FBC-OAUTH'), @('OAUTH2_', 'FBC-OAUTH'),
  @('INTEGRATION_', 'FBC-OAUTH'), @('WEBHOOKS_UPDATE', 'FBC-OAUTH'),
  @('USER_GUILD_SETTINGS_UPDATE', 'FBC-READSTATE'),
  @('USER_NON_CHANNEL_ACK', 'FBC-READSTATE'),
  @('USER_PAYMENT', 'FBC-COMMERCE'), @('USER_PREMIUM_', 'FBC-COMMERCE'),
  @('USER_SUBSCRIPTIONS_', 'FBC-COMMERCE'),
  @('USER_REQUIRED_ACTION_UPDATE', 'FBC-MODERATION'),
  @('USER_', 'FBC-PROFILE'),
  @('ENTITLEMENT_', 'FBC-COMMERCE'), @('GIFT_CODE_', 'FBC-COMMERCE'),
  @('BILLING_', 'FBC-COMMERCE'), @('PAYMENT_UPDATE', 'FBC-COMMERCE'),
  @('WALLET_', 'FBC-COMMERCE'), @('VIRTUAL_CURRENCY_', 'FBC-COMMERCE'),
  @('QUEST', 'FBC-COMMERCE'), @('WISHLIST_', 'FBC-COMMERCE'),
  @('PREMIUM_MARKETING_', 'FBC-COMMERCE'),
  @('CREATOR_MONETIZATION_', 'FBC-COMMERCE'),
  @('AUTH_SESSION_CHANGE', 'FBC-ACCOUNT'), @('AUTHENTICATOR_', 'FBC-ACCOUNT'),
  @('AUTO_MODERATION_', 'FBC-MODERATION'),
  @('CONVERSATION_SUMMARY_UPDATE', 'FBC-AI'),
  @('SOUNDBOARD_SOUNDS', 'FBC-EXPRESSION'),
  @('READY', 'FBC-GATEWAY'), @('RESUMED', 'FBC-GATEWAY'),
  @('SESSIONS_REPLACE', 'FBC-GATEWAY'), @('STATE_UPDATE', 'FBC-GATEWAY'),
  @('DELETED_ENTITY_IDS', 'FBC-GATEWAY'),
  @('EXPERIMENT_', 'FBC-PLATFORM'),
  @('CONTENT_INVENTORY_', 'FBC-PLATFORM')
)

function Get-FileDigest([string] $path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextDigest([string] $text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $sha.Dispose()
  }
}

function Get-InstalledClient([string] $root) {
  if (-not (Test-Path -LiteralPath $root)) {
    throw "Discord is not installed under the supplied root."
  }
  $app = Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if (-not $app) { throw 'No app-<version> directory was found.' }

  $artifacts = @()
  foreach ($file in Get-ChildItem -LiteralPath $app.FullName -File -Filter '*.exe') {
    $artifacts += [ordered]@{
      path = $file.Name; bytes = $file.Length; sha256 = Get-FileDigest $file.FullName
    }
  }
  $modules = @()
  $moduleRoot = Join-Path $app.FullName 'modules'
  if (Test-Path -LiteralPath $moduleRoot) {
    foreach ($module in Get-ChildItem -LiteralPath $moduleRoot -Directory | Sort-Object Name) {
      $files = Get-ChildItem -LiteralPath $module.FullName -Recurse -File |
        Where-Object { $_.Extension -in '.asar', '.node', '.dll' } |
        Sort-Object FullName
      $moduleArtifacts = @()
      foreach ($file in $files) {
        $relative = $file.FullName.Substring($module.FullName.Length + 1) -replace '\\', '/'
        $moduleArtifacts += [ordered]@{
          path = $relative; bytes = $file.Length; sha256 = Get-FileDigest $file.FullName
        }
      }
      $modules += [ordered]@{ name = $module.Name; artifacts = $moduleArtifacts }
    }
  }
  return [ordered]@{
    version = $app.Name -replace '^app-', ''
    artifacts = $artifacts
    modules = $modules
  }
}

function Get-RendererCorpus([string] $cache, [bool] $offline) {
  if (-not (Test-Path -LiteralPath $cache)) {
    [void] (New-Item -ItemType Directory -Path $cache -Force)
  }
  if (-not $offline) {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(180)
    try {
      $document = $client.GetStringAsync('https://discord.com/app').GetAwaiter().GetResult()
      $names = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($match in [regex]::Matches($document, '/assets/([A-Za-z0-9._-]+\.js)')) {
        [void] $names.Add($match.Groups[1].Value)
      }
      Save-RendererChunks $client $cache $names
      $entry = @($names | Where-Object { $_ -like 'web.*' })[0]
      $entryText = [IO.File]::ReadAllText((Join-Path $cache $entry))
      foreach ($name in Get-ChunkNames $entryText) { [void] $names.Add($name) }
      Save-RendererChunks $client $cache $names
    } finally {
      $client.Dispose()
    }
  }
  $files = Get-ChildItem -LiteralPath $cache -File -Filter '*.js' | Sort-Object Name
  if ($files.Count -eq 0) { throw 'The renderer cache is empty; run without -Offline.' }
  return $files
}

function Get-ChunkNames([string] $entryText) {
  $start = $entryText.IndexOf('T.u=e=>')
  if ($start -lt 0) { throw 'The renderer entry no longer exposes a chunk map.' }
  $end = $entryText.IndexOf(')[e]+".js"', $start)
  $segment = $entryText.Substring($start, $end - $start + 10)
  $split = $segment.LastIndexOf('({')
  $head = $segment.Substring(0, $split)
  $tail = $segment.Substring($split)
  $names = @()
  foreach ($m in [regex]::Matches($head, '"([0-9]{1,6})"===e\?""\+e\+"\.([0-9a-f]{16})\.js"')) {
    $names += "$($m.Groups[1].Value).$($m.Groups[2].Value).js"
  }
  foreach ($m in [regex]::Matches($head, '"([0-9]{1,6}\.[0-9a-f]{16}\.js)"')) {
    $names += $m.Groups[1].Value
  }
  foreach ($m in [regex]::Matches($tail, '"([0-9a-f]{16})"')) {
    $names += "$($m.Groups[1].Value).js"
  }
  return $names
}

function Save-RendererChunks($client, [string] $cache, $names) {
  $pending = New-Object System.Collections.ArrayList
  foreach ($name in $names) {
    $destination = Join-Path $cache $name
    if (Test-Path -LiteralPath $destination) { continue }
    [void] $pending.Add([pscustomobject]@{
      Task = $client.GetByteArrayAsync("https://discord.com/assets/$name")
      Path = $destination
    })
    if ($pending.Count -ge 32) { Complete-RendererChunks $pending }
  }
  Complete-RendererChunks $pending
}

function Complete-RendererChunks($pending) {
  foreach ($item in $pending) {
    try { [IO.File]::WriteAllBytes($item.Path, $item.Task.GetAwaiter().GetResult()) }
    catch { Write-Warning "Renderer chunk download failed: $($item.Path | Split-Path -Leaf)" }
  }
  $pending.Clear()
}

function Get-EndpointConstants($files) {
  $templates = [regex]::new('([A-Z][A-Z0-9_]{2,60})\s*:\s*(?:\(?[a-z,$]{0,12}\)?\s*=>\s*)?`(/[^`]{1,160})`')
  $literals = [regex]::new('([A-Z][A-Z0-9_]{2,60})\s*:\s*"(/[a-z0-9\-/@]{2,90})"')
  $endpoints = @{}
  foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($m in $templates.Matches($text)) { $endpoints[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in $literals.Matches($text)) {
      if (-not $endpoints.ContainsKey($m.Groups[1].Value)) {
        $endpoints[$m.Groups[1].Value] = $m.Groups[2].Value
      }
    }
  }
  return $endpoints
}

function Get-GatewayEvents($entryText) {
  $anchor = [regex]::Match($entryText, '([A-Za-z_$][\w$]*)\(\["READY_SUPPLEMENTAL"\]')
  if (-not $anchor.Success) { throw 'The renderer entry no longer registers READY_SUPPLEMENTAL.' }
  $registrar = [regex]::Escape($anchor.Groups[1].Value)
  $events = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($call in [regex]::Matches($entryText, $registrar + '\(\[((?:"[A-Z][A-Z0-9_]*"\s*,?\s*)+)\]')) {
    foreach ($name in [regex]::Matches($call.Groups[1].Value, '"([A-Z][A-Z0-9_]*)"')) {
      [void] $events.Add($name.Groups[1].Value)
    }
  }
  return $events
}

function Resolve-EventDomain([string] $event) {
  foreach ($rule in $script:EventRules) {
    if ($event.StartsWith($rule[0])) { return $rule[1] }
  }
  return $null
}

$installed = Get-InstalledClient $DiscordRoot
$files = Get-RendererCorpus $CacheDirectory $Offline.IsPresent
$entryFile = $files | Where-Object { $_.Name -like 'web.*' } | Select-Object -First 1
if (-not $entryFile) { throw 'The renderer entry chunk is missing from the cache.' }
$entryText = [IO.File]::ReadAllText($entryFile.FullName)

$corpusLines = foreach ($file in $files) { "$($file.Name) $(Get-FileDigest $file.FullName)" }
$endpoints = Get-EndpointConstants $files
$events = Get-GatewayEvents $entryText

$segments = @{}
foreach ($entry in $endpoints.GetEnumerator()) {
  $segment = ($entry.Value -split '/')[1]
  if ($segment -match '^\$') { $segment = '<dynamic>' }
  if (-not $segments.ContainsKey($segment)) { $segments[$segment] = 0 }
  $segments[$segment]++
}

$classified = [ordered]@{}
foreach ($domain in $script:Domains) {
  $classified[$domain] = [ordered]@{ segments = @(); endpointCount = 0; events = @() }
}
$unclassifiedSegments = @()
$unclassifiedEvents = @()

foreach ($segment in ($segments.Keys | Sort-Object)) {
  $domain = $null
  if ($script:SegmentDomains.ContainsKey($segment)) {
    $domain = $script:SegmentDomains[$segment]
  } elseif ($segment -eq '' -or $segment -eq '<dynamic>' -or $segment.Contains('?')) {
    $domain = 'FBC-PLATFORM'
  }
  if ($null -eq $domain) { $unclassifiedSegments += $segment; continue }
  $classified[$domain].segments += $segment
  $classified[$domain].endpointCount += $segments[$segment]
}

foreach ($event in ($events | Sort-Object)) {
  $domain = Resolve-EventDomain $event
  if ($null -eq $domain) { $unclassifiedEvents += $event; continue }
  $classified[$domain].events += $event
}

$classified['FBC-NATIVE'].nativeModules = @($installed.modules | ForEach-Object { $_.name })

$discovered = $segments.Count + $events.Count
$unclassified = $unclassifiedSegments.Count + $unclassifiedEvents.Count
$discoveryPercent = [math]::Round(100 * ($discovered - $unclassified) / [double] $discovered, 2)

$report = [ordered]@{
  schema = 1
  installedClient = $installed
  renderer = [ordered]@{
    entryChunk = $entryFile.Name
    chunkCount = $files.Count
    totalBytes = ($files | Measure-Object Length -Sum).Sum
    corpusDigest = Get-TextDigest (($corpusLines | Sort-Object) -join "`n")
  }
  symbols = [ordered]@{
    endpointConstants = $endpoints.Count
    endpointSegments = $segments.Count
    gatewayDispatchEvents = $events.Count
  }
  classification = $classified
  unclassified = [ordered]@{
    segments = $unclassifiedSegments
    gatewayDispatchEvents = $unclassifiedEvents
  }
  discoveryCoveragePercent = $discoveryPercent
}

$json = $report | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8

Write-Host "Discord $($installed.version): $($files.Count) renderer chunks."
Write-Host ("$($endpoints.Count) endpoint constants across " +
  "$($segments.Count) path segments, $($events.Count) Gateway dispatch events.")
Write-Host "Discovery coverage: $discoveryPercent%"

if ($unclassified -gt 0) {
  Write-Host 'Unclassified bundle capabilities (update docs/DISCORD_BUNDLE_COVERAGE.md):'
  foreach ($segment in $unclassifiedSegments) { Write-Host "  segment: $segment" }
  foreach ($event in $unclassifiedEvents) { Write-Host "  gateway event: $event" }
  exit 1
}

exit 0
