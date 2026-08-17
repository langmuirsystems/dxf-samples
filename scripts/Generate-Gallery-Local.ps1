#Requires -Version 7.0

<#
.SYNOPSIS
    Создает Markdown-файл с галереей изображений из папок в репозитории GitHub.

.DESCRIPTION
    Скрипт подключается к частному репозиторию GitHub с помощью токена доступа.
    Он сканирует указанную папку на наличие подпапок, в каждой из которых ищет PNG-файл.
    Затем он генерирует Markdown-файл, содержащий HTML-таблицу с изображениями,
    располагая не более 4 изображений в строке.

.PARAMETER GitHubToken
    Персональный токен доступа (PAT) для аутентификации в GitHub API.
    Токен должен иметь права на чтение репозитория ('repo').

.PARAMETER Owner
    Владелец репозитория (имя пользователя или организации).

.PARAMETER Repo
    Имя репозитория.

.PARAMETER Path
    Путь к папке внутри репозитория, содержащей подпапки с изображениями.

.PARAMETER OutputFile
    Путь для сохранения сгенерированного Markdown-файла. По умолчанию 'ImageGallery.md'.

.EXAMPLE
    .\Generate-Gallery.ps1 -GitHubToken "ghp_xxxxxxxx" -Owner "имя-пользователя" -Repo "мой-проект" -Path "assets/cad-previews"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $false)]
    [string]$Path = "",  # Default empty string for root directory

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "ImageGallery.md"
)

begin {
    # Настройка подключения к GitHub API
    $ApiBaseUrl = "https://api.github.com/repos/$Owner/$Repo/contents"
    $headers = @{
        "Authorization" = "Bearer $GitHubToken"
        "Accept"        = "application/vnd.github.v3+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    
    # Инициализация списка для данных изображений
    $imageData = [System.Collections.Generic.List[object]]::new()
    
    # Счетчики для статистики
    $processedFolders = 0
    $foundImages = 0
    $missingImages = 0
}

process {
    try {
        Write-Host "🚀 Начинаем создание галереи изображений..."
        
        # --- 1. Получение содержимого основной папки ---
        $uri = if ([string]::IsNullOrEmpty($Path)) {
            $ApiBaseUrl
        } else {
            "$ApiBaseUrl/$Path"
        }
        
        Write-Host "🔎 Получение списка подпапок из '$Path'..."
        $mainFolderContents = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        
        # --- 2. Фильтрация и обработка подпапок ---
        $subfolders = $mainFolderContents | Where-Object { $_.type -eq 'dir' }
        
        if (-not $subfolders) {
            Write-Warning "В папке '$Path' не найдено подпапок. Завершение работы."
            return
        }
        
        Write-Host "✅ Найдено $($subfolders.Count) подпапок. Обработка каждой..."
        
        # --- 3. Сбор информации об изображениях ---
        foreach ($folder in $subfolders) {
            $processedFolders++
            Write-Host "  - Обработка папки: $($folder.name)"
            
            try {
                $subfolderContents = Invoke-RestMethod -Uri $folder.url -Headers $headers -Method Get
                $pngFile = $subfolderContents | Where-Object { $_.Name -like '*.png' } | Select-Object -First 1
                
                if ($pngFile) {
                    $foundImages++
                    $imageData.Add([pscustomobject]@{
                        Name = [System.IO.Path]::GetFileNameWithoutExtension($pngFile.name)
                        Url  = $pngFile.download_url
                        Folder = $folder.name
                        # Ссылка на папку примера в репозитории (отдается GitHub API)
                        FolderUrl = $folder.html_url
                    })
                    Write-Host "    ✨ Найден PNG файл: $($pngFile.name)"
                } else {
                    $missingImages++
                    Write-Warning "    ⚠️ В папке $($folder.name) не найден PNG файл."
                }
            }
            catch {
                Write-Warning "    ⚠️ Ошибка при обработке папки $($folder.name): $($_.Exception.Message)"
                continue
            }
        }
        
        # --- 4. Проверка наличия данных ---
        if ($imageData.Count -eq 0) {
            Write-Host "Нет данных для создания галереи. Завершение работы."
            return
        }
        
        # --- 5. Генерация Markdown файла ---
        Write-Host "🖼️ Генерация Markdown файла с $($imageData.Count) изображениями..."
        
        $markdownLines = [System.Collections.Generic.List[string]]::new()
        $markdownLines.Add("# Галерея изображений")
        $markdownLines.Add("")
        $markdownLines.Add("<table>")
        
        # Группировка по 4 изображения в строку
        for ($i = 0; $i -lt $imageData.Count; $i += 4) {
            $markdownLines.Add("<tr>")
            
            for ($j = 0; $j -lt 4; $j++) {
                if ($i + $j -lt $imageData.Count) {
                    $image = $imageData[$i + $j]
$markdownLines.Add(@"
    <td align="center" valign="bottom" style="width:25%">
      <div style="height:400px; display:flex; align-items:center; justify-content:center">
        <a href="$($image.FolderUrl)"><img src="$($image.Url)" alt="$($image.Name)" style="max-height:400px; max-width:100%; object-fit:contain"></a>
      </div>
      <br>
      <b><a href="$($image.FolderUrl)">$($image.Name)</a></b><br>
      <small>($($image.Folder))</small>
    </td>
"@)
                } else {
                    # Пустая ячейка для выравнивания таблицы
                    $markdownLines.Add('    <td></td>')
                }
            }
            
            $markdownLines.Add("</tr>")
        }
        
        $markdownLines.Add("</table>")
        $markdownLines.Add("")
        $markdownLines.Add("> *Всего обработано папок: $processedFolders*")
        $markdownLines.Add("> *Найдено изображений: $foundImages*")
        $markdownLines.Add("> *Папок без изображений: $missingImages*")
        
        # --- 6. Сохранение файла ---
        try {
            Set-Content -Path $OutputFile -Value ($markdownLines -join "`n") -Encoding UTF8 -NoNewline
            Write-Host "✅ Успешно! Галерея сохранена в файл: $OutputFile"
            Write-Host "📊 Статистика:"
            Write-Host "   - Обработано папок: $processedFolders"
            Write-Host "   - Найдено изображений: $foundImages"
            Write-Host "   - Папок без изображений: $missingImages"
        }
        catch {
            Write-Error "❌ Не удалось сохранить файл $OutputFile."
            Write-Error $_.Exception.Message
        }
    }
    catch {
        Write-Error "❌ Произошла ошибка при обращении к GitHub API. Проверьте параметры и токен."
        Write-Error $_.Exception.Message
    }
}

end {
    # Очистка токена из памяти
    Remove-Variable -Name GitHubToken -ErrorAction SilentlyContinue
    [GC]::Collect()
}