param(
    [string]$InputFolder = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Remove-Diacritics {
    param([Parameter(Mandatory)] [string]$Text)

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    return $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function Convert-ToAsciiTransliteration {
    param([Parameter(Mandatory)] [string]$Text)

    $text = $Text.ToLowerInvariant()

    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $text.ToCharArray()) {
        switch ($char) {
            'а' { [void]$builder.Append('a') }
            'б' { [void]$builder.Append('b') }
            'в' { [void]$builder.Append('v') }
            'г' { [void]$builder.Append('g') }
            'д' { [void]$builder.Append('d') }
            'е' { [void]$builder.Append('e') }
            'ё' { [void]$builder.Append('yo') }
            'ж' { [void]$builder.Append('zh') }
            'з' { [void]$builder.Append('z') }
            'и' { [void]$builder.Append('i') }
            'й' { [void]$builder.Append('y') }
            'к' { [void]$builder.Append('k') }
            'л' { [void]$builder.Append('l') }
            'м' { [void]$builder.Append('m') }
            'н' { [void]$builder.Append('n') }
            'о' { [void]$builder.Append('o') }
            'п' { [void]$builder.Append('p') }
            'р' { [void]$builder.Append('r') }
            'с' { [void]$builder.Append('s') }
            'т' { [void]$builder.Append('t') }
            'у' { [void]$builder.Append('u') }
            'ф' { [void]$builder.Append('f') }
            'х' { [void]$builder.Append('kh') }
            'ц' { [void]$builder.Append('ts') }
            'ч' { [void]$builder.Append('ch') }
            'ш' { [void]$builder.Append('sh') }
            'щ' { [void]$builder.Append('shch') }
            'ъ' { }
            'ы' { [void]$builder.Append('y') }
            'ь' { }
            'э' { [void]$builder.Append('e') }
            'ю' { [void]$builder.Append('yu') }
            'я' { [void]$builder.Append('ya') }
            'ї' { [void]$builder.Append('yi') }
            'і' { [void]$builder.Append('i') }
            'є' { [void]$builder.Append('ye') }
            'ґ' { [void]$builder.Append('g') }
            'א' { [void]$builder.Append('a') }
            'ב' { [void]$builder.Append('b') }
            'ג' { [void]$builder.Append('g') }
            'ד' { [void]$builder.Append('d') }
            'ה' { [void]$builder.Append('h') }
            'ו' { [void]$builder.Append('v') }
            'ז' { [void]$builder.Append('z') }
            'ח' { [void]$builder.Append('kh') }
            'ט' { [void]$builder.Append('t') }
            'י' { [void]$builder.Append('y') }
            'כ' { [void]$builder.Append('k') }
            'ך' { [void]$builder.Append('k') }
            'ל' { [void]$builder.Append('l') }
            'מ' { [void]$builder.Append('m') }
            'ם' { [void]$builder.Append('m') }
            'נ' { [void]$builder.Append('n') }
            'ן' { [void]$builder.Append('n') }
            'ס' { [void]$builder.Append('s') }
            'ע' { [void]$builder.Append('a') }
            'פ' { [void]$builder.Append('p') }
            'ף' { [void]$builder.Append('p') }
            'צ' { [void]$builder.Append('ts') }
            'ץ' { [void]$builder.Append('ts') }
            'ק' { [void]$builder.Append('k') }
            'ר' { [void]$builder.Append('r') }
            'ש' { [void]$builder.Append('sh') }
            'ת' { [void]$builder.Append('t') }
            'α' { [void]$builder.Append('a') }
            'β' { [void]$builder.Append('v') }
            'γ' { [void]$builder.Append('g') }
            'δ' { [void]$builder.Append('d') }
            'ε' { [void]$builder.Append('e') }
            'ζ' { [void]$builder.Append('z') }
            'η' { [void]$builder.Append('i') }
            'θ' { [void]$builder.Append('th') }
            'ι' { [void]$builder.Append('i') }
            'κ' { [void]$builder.Append('k') }
            'λ' { [void]$builder.Append('l') }
            'μ' { [void]$builder.Append('m') }
            'ν' { [void]$builder.Append('n') }
            'ξ' { [void]$builder.Append('x') }
            'ο' { [void]$builder.Append('o') }
            'π' { [void]$builder.Append('p') }
            'ρ' { [void]$builder.Append('r') }
            'σ' { [void]$builder.Append('s') }
            'ς' { [void]$builder.Append('s') }
            'τ' { [void]$builder.Append('t') }
            'υ' { [void]$builder.Append('y') }
            'φ' { [void]$builder.Append('f') }
            'χ' { [void]$builder.Append('kh') }
            'ψ' { [void]$builder.Append('ps') }
            'ω' { [void]$builder.Append('o') }
            default { [void]$builder.Append($char) }
        }
    }

    return $builder.ToString()
}

function TitleCase-Simple {
    param([Parameter(Mandatory)] [string]$Text)

    $words = $Text.ToLowerInvariant() -split '\s+'
    $cased = foreach ($word in $words) {
        if (-not $word) { continue }
        if ($word.Length -eq 1) {
            $word.ToUpperInvariant()
        }
        else {
            $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)
        }
    }

    return ($cased -join ' ')
}

function Normalize-NamePart {
    param([Parameter(Mandatory)] [string]$Text)

    $value = Convert-ToAsciiTransliteration $Text
    $value = Remove-Diacritics $value
    $value = $value -replace '\b(official|audio|video|lyrics|lyric|mix|playlist|version|remix|topic|full|hd|4k|extended|edit|visualizer)\b', ' '
    $value = $value -replace '\[[^\]]*\]', ' '
    $value = $value -replace '\([^\)]*\)', ' '
    $value = $value -replace '\{[^\}]*\}', ' '
    $value = $value -replace '[^A-Za-z0-9 -]', ' '
    $value = $value -replace '\s+', ' '
    $value = $value.Trim()
    if (-not $value) {
        return $null
    }

    return (TitleCase-Simple $value)
}

function Clean-SearchQuery {
    param([Parameter(Mandatory)] [string]$Text)

    $value = Convert-ToAsciiTransliteration $Text
    $value = Remove-Diacritics $value
    $value = $value -replace '\[[^\]]*\]', ' '
    $value = $value -replace '\([^\)]*\)', ' '
    $value = $value -replace '\{[^\}]*\}', ' '
    $value = $value -replace '\b(official|audio|video|lyrics|lyric|mix|playlist|version|remix|hour|hours|full|hd|4k)\b', ' '
    $value = $value -replace '[^A-Za-z0-9 ]', ' '
    $value = $value -replace '\b\d{3,}\b', ' '
    $value = $value -replace '\s+', ' '
    return $value.Trim()
}

function Get-QueryFromFileName {
    param([Parameter(Mandatory)] [string]$FileName)

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $query = Clean-SearchQuery $base
    if ([string]::IsNullOrWhiteSpace($query)) {
        return $null
    }

    return $query
}

function Get-LocalPartsFromFileName {
    param([Parameter(Mandatory)] [string]$FileName)

    function Has-ArtistSignal {
        param([Parameter(Mandatory)] [string]$Text)
        return ($Text -match '&|,|\bfeat\b|\bft\b|\bx\b|\band\b')
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $bracketAuthor = $null
    $rest = $base

    if ($base -match '^\s*\[(?<author>[^\]]+)\]\s*(?<rest>.+)$') {
        $bracketAuthor = Normalize-NamePart $Matches['author']
        $rest = $Matches['rest']
    }

    if (-not $bracketAuthor) {
        return [pscustomobject]@{ Author = $null; Title = $null }
    }

    $isTopic = $bracketAuthor -match '\btopic\b'
    $authorPart = Normalize-NamePart (($bracketAuthor -replace '\s*-\s*Topic$', '').Trim())

    $cleanTitle = ($rest -replace '\s*[\(\[\{｜|].*$', '')
    $cleanTitle = Normalize-NamePart $cleanTitle
    if (-not $cleanTitle) {
        return [pscustomobject]@{ Author = $null; Title = $null }
    }

    if ($rest -match '^(?<left>.+?)\s+[-–—:]\s+(?<right>.+)$') {
        $rawLeft = $Matches['left'].Trim()
        $rawRight = $Matches['right'].Trim()
        $left = Normalize-NamePart $rawLeft
        $right = Normalize-NamePart $rawRight

        if ($left -and $right) {
            if ($isTopic) {
                return [pscustomobject]@{
                    Author = $left
                    Title  = $right
                }
            }

            if (Has-ArtistSignal $rawLeft) {
                return [pscustomobject]@{
                    Author = $left
                    Title  = $right
                }
            }

            if ($left -eq $authorPart -or $rawLeft -like "*$authorPart*") {
                return [pscustomobject]@{
                    Author = $authorPart
                    Title  = $right
                }
            }

            return [pscustomobject]@{
                Author = $authorPart
                Title  = $left
            }
        }
    }

    return [pscustomobject]@{
        Author = $authorPart
        Title  = $cleanTitle
    }
}

function Get-TextFromNode {
    param([Parameter(Mandatory)] $Node)

    if ($null -eq $Node) {
        return $null
    }

    if ($Node.PSObject.Properties.Name -contains 'simpleText') {
        return [string]$Node.simpleText
    }

    if ($Node.PSObject.Properties.Name -contains 'runs') {
        return (($Node.runs | ForEach-Object { $_.text }) -join '')
    }

    return $null
}

function Find-FirstPropertyNode {
    param(
        [Parameter(Mandatory)] $Node,
        [Parameter(Mandatory)] [string]$PropertyName
    )

    if ($null -eq $Node) {
        return $null
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            $found = Find-FirstPropertyNode -Node $item -PropertyName $PropertyName
            if ($found) { return $found }
        }
        return $null
    }

    if ($Node.PSObject.Properties.Name -contains $PropertyName) {
        return $Node.$PropertyName
    }

    foreach ($prop in $Node.PSObject.Properties) {
        $found = Find-FirstPropertyNode -Node $prop.Value -PropertyName $PropertyName
        if ($found) { return $found }
    }

    return $null
}

function Search-YouTubeResult {
    param([Parameter(Mandatory)] [string]$Query)

    $encoded = [uri]::EscapeDataString($Query)
    $url = "https://www.youtube.com/results?search_query=$encoded&hl=en&gl=US"
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
    }

    $response = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
    $match = [regex]::Match($response.Content, 'var ytInitialData = (?<json>\{.*?\});</script>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        return $null
    }

    $data = $match.Groups['json'].Value | ConvertFrom-Json
    $video = Find-FirstPropertyNode -Node $data -PropertyName 'videoRenderer'
    if (-not $video) {
        return $null
    }

    $title = Get-TextFromNode $video.title
    $channel = if ($video.PSObject.Properties.Name -contains 'ownerText') { Get-TextFromNode $video.ownerText } else { $null }

    return [pscustomobject]@{
        Title   = $title
        Channel = $channel
    }
}

function Get-CanonicalParts {
    param(
        [Parameter(Mandatory)] [string]$Query,
        [Parameter(Mandatory)] [string]$FallbackName
    )

    $local = Get-LocalPartsFromFileName -FileName $FallbackName

    $result = $null
    if ($Query) {
        try {
            $result = Search-YouTubeResult -Query $Query
        }
        catch {
            $result = $null
        }
    }

    $author = $null
    $title = $null

    if ($local.Author) {
        $author = $local.Author
    }

    if ($local.Title) {
        $title = $local.Title
    }

    if ($result) {
        $youtubeAuthor = Normalize-NamePart (($result.Channel -replace '\s*-\s*Topic$', '').Trim())
        $youtubeTitle = Normalize-NamePart ($result.Title)

        if (-not $author -and $youtubeAuthor) {
            $author = $youtubeAuthor
        }

        if (-not $title -and $youtubeTitle) {
            $title = $youtubeTitle
        }
    }

    if (-not $author) { $author = 'Unknown Artist' }
    if (-not $title) { $title = 'Unknown Title' }

    return [pscustomobject]@{
        Author = $author
        Title  = $title
    }
}

$files = Get-ChildItem -LiteralPath $InputFolder -File -Filter '*.mp3' | Sort-Object Name
if (-not $files) {
    Write-Host "No MP3 files found in '$InputFolder'."
    exit 0
}

foreach ($file in $files) {
    if ($file.Name -notmatch '^\s*\[') {
        continue
    }

    try {
        $query = Get-QueryFromFileName -FileName $file.Name
        $parts = Get-CanonicalParts -Query $query -FallbackName $file.BaseName

        $newName = '{0} - {1}.mp3' -f $parts.Author, $parts.Title
        $newName = $newName -replace '\s+', ' '
        $newName = $newName -replace '\s*-\s*-\s*', ' - '
        $newName = $newName.Trim()

        $destination = Join-Path $file.DirectoryName $newName
        $counter = 1
        while (Test-Path -LiteralPath $destination) {
            $destination = Join-Path $file.DirectoryName ('{0} - {1} ({2}).mp3' -f $parts.Author, $parts.Title, $counter)
            $counter++
        }

        if ($file.Name -eq [System.IO.Path]::GetFileName($destination)) {
            Write-Host "Skipping already-normalized file: $($file.Name)"
            continue
        }

        Write-Host "Renaming: $($file.Name) -> $(Split-Path -Leaf $destination)"
        if (-not $DryRun) {
            [System.IO.File]::Move($file.FullName, $destination)
        }
    }
    catch {
        Write-Warning "Failed to rename '$($file.Name)': $($_.Exception.Message)"
    }
}
