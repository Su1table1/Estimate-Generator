Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# !!!MAIN FORM!!!

# =========================================================
# APP PATH / SETTINGS CONFIG
# =========================================================

$appFolder = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
$appSettingsPath = Join-Path $appFolder "appsettings.json"

if (Test-Path $appSettingsPath) {
    $settings = Get-Content $appSettingsPath -Raw | ConvertFrom-Json

    $script:TemplatesFolder = $settings.TemplatesFolder
    $script:TemplateJsonPath = $settings.TemplatesJson
}
else {
    $script:TemplatesFolder = Join-Path $appFolder "Templates"
    $script:TemplateJsonPath = Join-Path $script:TemplatesFolder "Templates.json"
}

if ([string]::IsNullOrWhiteSpace($script:TemplatesFolder)) {
    $script:TemplatesFolder = Join-Path $appFolder "Templates"
}

if ([string]::IsNullOrWhiteSpace($script:TemplateJsonPath)) {
    $script:TemplateJsonPath = Join-Path $script:TemplatesFolder "Templates.json"
}

if (-not (Test-Path $script:TemplatesFolder)) {
    New-Item -ItemType Directory -Path $script:TemplatesFolder -Force | Out-Null
}

if (-not (Test-Path $script:TemplateJsonPath)) {
    '{}' | Set-Content -Path $script:TemplateJsonPath -Encoding UTF8
}

$templateFolder = $script:TemplatesFolder
$templateConfigPath = $script:TemplateJsonPath

# =========================================================
# HELPER FUNCTIONS
# =========================================================


function Convert-TemplateNameToFileName {
    param (
        [string]$name
    )

    $safeName = $name.Trim()
    $safeName = $safeName -replace '[^\w\s-]', ''
    $safeName = $safeName -replace '\s+', '_'

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return "Untitled_Template.txt"
    }

    return "$safeName.txt"
}

function Convert-FieldNameForDisplay {
    param (
        [string]$fieldName
    )

    return (($fieldName.ToLower() -split "_") | ForEach-Object {
        if ($_.Length -gt 0) {
            $_.Substring(0,1).ToUpper() + $_.Substring(1)
        }
    }) -join "_"
}

function Get-TemplateFieldsFromContent {
    param (
        [string]$content
    )

    $matches = [regex]::Matches($content, '%%([A-Z0-9_]+)%%')

    $fields = @()

    foreach ($match in $matches) {
        $field = $match.Groups[1].Value

        if ($fields -notcontains $field) {
            $fields += $field
        }
    }

    return $fields
}

function Convert-FieldNameToPlaceholder {
    param (
        [string]$fieldName
    )

    $safeName = $fieldName.Trim().ToUpper()
    $safeName = $safeName -replace '[^A-Z0-9\s_]', ''
    $safeName = $safeName -replace '[\s_]+', '_'
    $safeName = $safeName.Trim('_')

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return ""
    }

    return "%%$safeName%%"
}

function Sync-TemplatesJsonWithFolder {
	Ensure-TemplateStorageExists
    if (-not (Test-Path $templateFolder)) {
        New-Item -ItemType Directory -Path $templateFolder -Force | Out-Null
    }

    if (-not (Test-Path $templateConfigPath)) {
        '{}' | Set-Content -Path $templateConfigPath -Encoding UTF8
    }

    try {
        $config = Get-Content $templateConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        $config = [PSCustomObject]@{}
    }

    if ($null -eq $config) {
        $config = [PSCustomObject]@{}
    }

    $templateFiles = Get-ChildItem -Path $templateFolder -Filter "*.txt" -File

    foreach ($file in $templateFiles) {
        $alreadyExists = $false

        foreach ($property in $config.PSObject.Properties) {
            if ($null -ne $property.Value -and $property.Value.file -eq $file.Name) {
                $alreadyExists = $true
                break
            }
        }

        if (-not $alreadyExists) {
            $templateName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $templateName = $templateName -replace '_', ' '

            $content = Get-Content $file.FullName -Raw
            $fields = Get-TemplateFieldsFromContent $content

            $displayFields = @()
            foreach ($field in $fields) {
                $displayFields += Convert-FieldNameForDisplay $field
            }

            $config | Add-Member -MemberType NoteProperty -Name $templateName -Value ([PSCustomObject]@{
                file = $file.Name
                fields = $displayFields
            }) -Force
        }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $templateConfigPath -Encoding UTF8

    return $config
}

function Refresh-TemplateDropdown {
    if ($null -eq $templateDropdown) {
        return
    }

    $currentSelection = $templateDropdown.SelectedItem

    $templateDropdown.Items.Clear()
    [void]$templateDropdown.Items.Add("")

    if ($null -ne $script:templateConfig) {
        foreach ($templateName in ($script:templateConfig.PSObject.Properties.Name | Sort-Object)) {
            [void]$templateDropdown.Items.Add($templateName)
        }
    }

    $templateDropdown.MaxDropDownItems = [Math]::Min($templateDropdown.Items.Count, 50)

    if ($currentSelection -and $templateDropdown.Items.Contains($currentSelection)) {
        $templateDropdown.SelectedItem = $currentSelection
    }
    else {
        $templateDropdown.SelectedIndex = 0
    }
}

function Ensure-TemplateStorageExists {

    if (-not (Test-Path $script:TemplatesFolder)) {
        New-Item -ItemType Directory -Path $script:TemplatesFolder -Force | Out-Null
    }

    if (-not (Test-Path $script:TemplateJsonPath)) {
        '{}' | Set-Content -Path $script:TemplateJsonPath -Encoding UTF8
    }
}

# =========================================================
# LOAD TEMPLATE CONFIG
# =========================================================
$script:templateConfig = Sync-TemplatesJsonWithFolder

if (!(Test-Path $templateConfigPath)) {
    '{}' | Set-Content -Path $templateConfigPath -Encoding UTF8
}

try {
    $templateConfig = Sync-TemplatesJsonWithFolder
}
catch {
    '{}' | Set-Content -Path $templateConfigPath -Encoding UTF8
    $templateConfig = @{}
}

# =========================================================
# MAIN FORM
# =========================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Estimate Request Generator"
$form.Size = New-Object System.Drawing.Size(1200,850)
$form.MinimumSize = New-Object System.Drawing.Size(900,730)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI",11)
$form.AutoScaleMode = "Dpi"

# =========================================================
# TEMPLATE LABEL
# =========================================================

$templateLabel = New-Object System.Windows.Forms.Label
$templateLabel.Text = "Template:"
$templateLabel.Location = New-Object System.Drawing.Point(10,15)
$templateLabel.Size = New-Object System.Drawing.Size(80,30)
$templateLabel.Anchor = "Top,Left"

$form.Controls.Add($templateLabel)

# =========================================================
# TEMPLATE DROPDOWN
# =========================================================

$templateDropdown = New-Object System.Windows.Forms.ComboBox
$templateDropdown.Location = New-Object System.Drawing.Point(95,10)
$templateDropdown.Size = New-Object System.Drawing.Size(350,35)
$templateDropdown.DropDownStyle = "DropDownList"
$templateDropdown.Anchor = "Top,Left"

# Blank/default selection
[void]$templateDropdown.Items.Add("")

$templateConfig.PSObject.Properties.Name |
    Sort-Object |
    ForEach-Object {
        [void]$templateDropdown.Items.Add($_)
    }

$templateDropdown.MaxDropDownItems = [Math]::Min($templateDropdown.Items.Count, 50)

# Start with blank selection
$templateDropdown.SelectedIndex = 0

$form.Controls.Add($templateDropdown)

# =========================================================
# EDIT TEMPLATES BUTTON
# =========================================================

$editTemplatesButton = New-Object System.Windows.Forms.Button
$editTemplatesButton.Text = "Edit Templates"
$editTemplatesButton.Location = New-Object System.Drawing.Point(460,10)
$editTemplatesButton.Size = New-Object System.Drawing.Size(140,35)
$editTemplatesButton.Anchor = "Top,Left"

$editTemplatesButton.Add_Click({
    $script:templateConfig = Sync-TemplatesJsonWithFolder
    Refresh-TemplateDropdown
    Show-TemplateEditor
})

$form.Controls.Add($editTemplatesButton)
# =========================================================
# INPUT PANEL
# =========================================================

$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Location = New-Object System.Drawing.Point(10,60)
$inputPanel.Size = New-Object System.Drawing.Size(1150,260)
$inputPanel.AutoScroll = $true
$inputPanel.Anchor = "Top,Left,Right"

$form.Controls.Add($inputPanel)

# =========================================================
# PREVIEW LABEL
# =========================================================

$previewLabel = New-Object System.Windows.Forms.Label
$previewLabel.Text = "Preview"
$previewLabel.Location = New-Object System.Drawing.Point(10,330)
$previewLabel.Size = New-Object System.Drawing.Size(100,30)
$previewLabel.Anchor = "Top,Left"

$form.Controls.Add($previewLabel)

# =========================================================
# PREVIEW BOX
# =========================================================

$previewBox = New-Object System.Windows.Forms.RichTextBox
$previewBox.Location = New-Object System.Drawing.Point(10,360)
$previewBox.Size = New-Object System.Drawing.Size(1150,390)
$previewBox.ReadOnly = $true
$previewBox.Font = New-Object System.Drawing.Font("Consolas",12)
$previewBox.Anchor = "Top,Bottom,Left,Right"

$form.Controls.Add($previewBox)

# =========================================================
# COPY BUTTON
# =========================================================

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy to Clipboard"
$copyButton.Location = New-Object System.Drawing.Point(10,765)
$copyButton.Size = New-Object System.Drawing.Size(180,40)
$copyButton.Anchor = "Bottom,Left"

$copyButton.Add_Click({

    if ($templateDropdown.SelectedIndex -le 0 -or [string]::IsNullOrWhiteSpace($templateDropdown.SelectedItem)) {
        $statusLabel.Text = "Select a template before copying."
        $statusTimer.Stop()
        $statusTimer.Start()
        return
    }

    $missingFields = @()

    foreach ($control in $inputPanel.Controls) {
        if ($control -is [System.Windows.Forms.TextBox]) {
            if ([string]::IsNullOrWhiteSpace($control.Text)) {
                $missingFields += $control.Tag
            }
        }
    }

    if ($missingFields.Count -gt 0) {
        $statusLabel.Text = "Fill in all input fields before copying."
        $statusTimer.Stop()
        $statusTimer.Start()
        return
    }

    if ([string]::IsNullOrWhiteSpace($previewBox.Text)) {
        $statusLabel.Text = "Nothing to copy."
        $statusTimer.Stop()
        $statusTimer.Start()
        return
    }

    Set-Clipboard -Value $previewBox.Text

    $statusLabel.Text = "Copied to clipboard."
    $statusTimer.Stop()
    $statusTimer.Start()
})

$form.Controls.Add($copyButton)

# =========================================================
# CLEAR BUTTON
# =========================================================

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "Clear"
$clearButton.Location = New-Object System.Drawing.Point(200,765)
$clearButton.Size = New-Object System.Drawing.Size(120,40)
$clearButton.Anchor = "Bottom,Left"

$clearButton.Add_Click({

    foreach ($textbox in $fieldControls.Values) {
        $textbox.Text = ""
    }

    Update-Preview

    $statusLabel.Text = "Cleared."

    $statusTimer.Stop()
    $statusTimer.Start()
})

$form.Controls.Add($clearButton)

# =========================================================
# STATUS LABEL
# =========================================================

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(340,772)
$statusLabel.Size = New-Object System.Drawing.Size(400,30)
$statusLabel.Anchor = "Bottom,Left"

$form.Controls.Add($statusLabel)

# =========================================================
# STATUS MESSAGE TIMER
# =========================================================

$statusTimer = New-Object System.Windows.Forms.Timer
$statusTimer.Interval = 5000

$statusTimer.Add_Tick({

    $statusLabel.Text = ""

    $statusTimer.Stop()
})

# =========================================================
# GLOBAL FIELD STORAGE
# =========================================================

$fieldControls = @{}

# =========================================================
# UPDATE PREVIEW
# =========================================================

function Update-Preview {

    if ($templateDropdown.SelectedItem -eq $null) {
        return
    }

    $selectedTemplate = $templateDropdown.SelectedItem.ToString()

    $templateInfo = $templateConfig.$selectedTemplate

    $templatePath = Join-Path $templateFolder $templateInfo.file

    if (!(Test-Path $templatePath)) {
        $previewBox.Text = "Template file not found."
        return
    }

    $content = Get-Content $templatePath -Raw

    foreach ($field in $fieldControls.Keys) {

        $value = $fieldControls[$field].Text

        $placeholder = "%%$($field.ToUpper())%%"

        $content = $content -replace [regex]::Escape($placeholder), $value
    }

    $previewBox.Text = $content
}

# =========================================================
# BUILD INPUT FIELDS
# =========================================================

function Build-InputFields {

    $inputPanel.Controls.Clear()
    $fieldControls.Clear()

    if ($templateDropdown.SelectedItem -eq $null) {
        return
    }

    $selectedTemplate = $templateDropdown.SelectedItem.ToString()

    $templateInfo = $templateConfig.$selectedTemplate

    $y = 10

    foreach ($field in $templateInfo.fields) {

        $label = New-Object System.Windows.Forms.Label
        $label.Text = ($field -replace "_"," ")
        $label.Location = New-Object System.Drawing.Point(10,$y)
        $label.Size = New-Object System.Drawing.Size(220,32)

        $textbox = New-Object System.Windows.Forms.TextBox
		$textbox.Location = New-Object System.Drawing.Point(240,$y)

		$textboxWidth = [Math]::Max(250, $inputPanel.Width - 270)

		$textbox.Size = New-Object System.Drawing.Size($textboxWidth,32)

		$textbox.Anchor = "Top,Left,Right"

        $textbox.Add_TextChanged({
            Update-Preview
        })

        $inputPanel.Controls.Add($label)
        $inputPanel.Controls.Add($textbox)

        $fieldControls[$field] = $textbox

        $y += 45
    }

    Update-Preview
}

# =========================================================
# TEMPLATE CHANGED EVENT
# =========================================================

$templateDropdown.Add_SelectedIndexChanged({

    if ([string]::IsNullOrWhiteSpace($templateDropdown.SelectedItem)) {
        $inputPanel.Controls.Clear()
        $fieldControls.Clear()
        $previewBox.Text = ""
        return
    }

    Build-InputFields
})

# =========================================================
# CLEAR BUTTON EVENT
# =========================================================

$clearButton.Add_Click({

    foreach ($textbox in $fieldControls.Values) {
        $textbox.Text = ""
    }

    Update-Preview

    $statusLabel.Text = "Cleared."
})

# =========================================================
# RESPONSIVE RESIZE HANDLER
# =========================================================

$form.Add_Resize({

    $inputPanel.Width = $form.ClientSize.Width - 35

    $previewBox.Width = $form.ClientSize.Width - 35
    $previewBox.Height = $form.ClientSize.Height - 460

    $copyButton.Top = $form.ClientSize.Height - 55
    $clearButton.Top = $form.ClientSize.Height - 55
    $statusLabel.Top = $form.ClientSize.Height - 48
})

# =========================================================
# !!!FIELD INSERT FORM!!!
# =========================================================

function Show-FieldInsertWindow {
    param (
        [System.Windows.Forms.Form]$owner,
        [System.Windows.Forms.TextBox]$contentBox,
        $templateConfig
    )

    $insertStart = $contentBox.SelectionStart
    $insertLength = $contentBox.SelectionLength

    $fieldWindow = New-Object System.Windows.Forms.Form
    $fieldWindow.Text = "Insert Input Field"
    $fieldWindow.Size = New-Object System.Drawing.Size(500,300)
    $fieldWindow.StartPosition = "CenterParent"
    $fieldWindow.Font = New-Object System.Drawing.Font("Segoe UI",11)
    $fieldWindow.FormBorderStyle = "FixedDialog"
    $fieldWindow.MaximizeBox = $false
    $fieldWindow.MinimizeBox = $false

    $fieldDropdown = New-Object System.Windows.Forms.ComboBox
    $fieldDropdown.Location = New-Object System.Drawing.Point(20,20)
    $fieldDropdown.Size = New-Object System.Drawing.Size(440,35)
    $fieldDropdown.DropDownStyle = "DropDownList"

    [void]$fieldDropdown.Items.Add("Create New Input Field")
	
	$isPopulatingFieldFromDropdown = $false

    $usedFields = @()

    foreach ($template in $templateConfig.PSObject.Properties) {
        foreach ($field in $template.Value.fields) {
            if (-not [string]::IsNullOrWhiteSpace($field)) {
                $usedFields += $field
            }
        }
    }

	$usedFields |
		Sort-Object -Unique |
		ForEach-Object {

			$displayName = ($_ -replace "_", " ")

			[void]$fieldDropdown.Items.Add($displayName)
		}

    $fieldDropdown.SelectedIndex = 0
    $fieldWindow.Controls.Add($fieldDropdown)

    $fieldNameLabel = New-Object System.Windows.Forms.Label
    $fieldNameLabel.Text = " Input Field Name:"
    $fieldNameLabel.Location = New-Object System.Drawing.Point(20,70)
    $fieldNameLabel.Size = New-Object System.Drawing.Size(200,25)
    $fieldWindow.Controls.Add($fieldNameLabel)

    $fieldNameBox = New-Object System.Windows.Forms.TextBox
    $fieldNameBox.Location = New-Object System.Drawing.Point(20,95)
    $fieldNameBox.Size = New-Object System.Drawing.Size(440,30)
    $fieldWindow.Controls.Add($fieldNameBox)

    $placeholderLabel = New-Object System.Windows.Forms.Label
    $placeholderLabel.Text = "Entering into template:"
    $placeholderLabel.Location = New-Object System.Drawing.Point(20,140)
    $placeholderLabel.Size = New-Object System.Drawing.Size(250,25)
    $fieldWindow.Controls.Add($placeholderLabel)

    $placeholderBox = New-Object System.Windows.Forms.TextBox
    $placeholderBox.Location = New-Object System.Drawing.Point(20,165)
    $placeholderBox.Size = New-Object System.Drawing.Size(440,30)
    $placeholderBox.ReadOnly = $true
    $placeholderBox.BackColor = [System.Drawing.Color]::LightGray
    $placeholderBox.ForeColor = [System.Drawing.Color]::DimGray
    $fieldWindow.Controls.Add($placeholderBox)

	$fieldNameBox.Add_TextChanged({

		$placeholderBox.Text = Convert-FieldNameToPlaceholder -fieldName $fieldNameBox.Text

		if ($isPopulatingFieldFromDropdown -eq $false) {
			$fieldDropdown.SelectedItem = "Create New Input Field"
		}
	})

	$fieldDropdown.Add_SelectedIndexChanged({

		if ($fieldDropdown.SelectedItem -eq "Create New Input Field") {
			return
		}

		$isPopulatingFieldFromDropdown = $true

		$fieldNameBox.Text = $fieldDropdown.SelectedItem.ToString()
		$placeholderBox.Text = Convert-FieldNameToPlaceholder -fieldName $fieldDropdown.SelectedItem.ToString()

		$isPopulatingFieldFromDropdown = $false
	})

    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = "Add Input Field"
    $addButton.Location = New-Object System.Drawing.Point(20,215)
    $addButton.Size = New-Object System.Drawing.Size(120,35)

    $addButton.Add_Click({

        if ([string]::IsNullOrWhiteSpace($placeholderBox.Text)) {
            return
        }

        $contentBox.Select($insertStart, $insertLength)
        $contentBox.SelectedText = $placeholderBox.Text
        $contentBox.Focus()

        $fieldWindow.Close()
    })

    $fieldWindow.Controls.Add($addButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(150,215)
    $cancelButton.Size = New-Object System.Drawing.Size(120,35)

    $cancelButton.Add_Click({
        $fieldWindow.Close()
    })

    $fieldWindow.Controls.Add($cancelButton)

    [void]$fieldWindow.ShowDialog($owner)
}

# =========================================================
# !!!EDITOR FORM!!!
# =========================================================
function Show-TemplateEditor {
	$script:templateConfig = Sync-TemplatesJsonWithFolder

    $editor = New-Object System.Windows.Forms.Form
	$editor.Text = "Template Editor"
	$editor.Size = New-Object System.Drawing.Size(900,700)
	$editor.MinimumSize = New-Object System.Drawing.Size(850,570)
	$editor.StartPosition = "CenterScreen"
	$editor.Font = New-Object System.Drawing.Font("Segoe UI",11)
	$editor.AutoScaleMode = "Dpi"
	$script:isAddingNewTemplate = $false
	$hasAutoCreatedTemplateListItem = $false

    # =========================
	# ADD TEMPLATE BUTTON
	# =========================

	$addTemplateButton = New-Object System.Windows.Forms.Button
	$addTemplateButton.Text = "Add Template"
	$addTemplateButton.Location = New-Object System.Drawing.Point(10,10)
	$addTemplateButton.Size = New-Object System.Drawing.Size(250,35)
	$addTemplateButton.Anchor = "Top,Left"

	$addTemplateButton.Add_Click({
		$script:isAddingNewTemplate = $true
		$list.ClearSelected()

		$nameBox.Text = "Untitled Template"
		$fileBox.Text = "Untitled_Template.txt"
		$fieldsBox.Text = ""
		$contentBox.Text = ""

		if (-not $list.Items.Contains("Untitled Template")) {
			[void]$list.Items.Add("Untitled Template")
		}

		$list.SelectedItem = "Untitled Template"
	})

	$editor.Controls.Add($addTemplateButton)

	# =========================
	# REFRESH TEMPLATES BUTTON
	# =========================

	$refreshTemplatesButton = New-Object System.Windows.Forms.Button
	$refreshTemplatesButton.Text = "Refresh List"
	$refreshTemplatesButton.Location = New-Object System.Drawing.Point(10,55)
	$refreshTemplatesButton.Size = New-Object System.Drawing.Size(250,35)
	$refreshTemplatesButton.Anchor = "Top,Left"

	$refreshTemplatesButton.Add_Click({
		$script:templateConfig = Sync-TemplatesJsonWithFolder

		$list.Items.Clear()

		foreach ($templateName in ($script:templateConfig.PSObject.Properties.Name | Sort-Object)) {
			[void]$list.Items.Add($templateName)
		}

		$nameBox.Text = ""
		$fileBox.Text = ""
		$fieldsBox.Text = ""
		$contentBox.Text = ""

		$editorStatusLabel.Text = "Template list refreshed."
		$editorStatusTimer.Stop()
		$editorStatusTimer.Start()
	})

	$editor.Controls.Add($refreshTemplatesButton)
		
	# =========================
    # TEMPLATE LIST
    # =========================
    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(10,100)
    $list.Size = New-Object System.Drawing.Size(250,475)
	$list.Anchor = "Top,Bottom,Left"

    $templateConfig.PSObject.Properties.Name | Sort-Object | ForEach-Object {
        [void]$list.Items.Add($_)
    }

    $editor.Controls.Add($list)
	
	# =========================
	# DELETE TEMPLATE BUTTON
	# =========================

	$deleteTemplateButton = New-Object System.Windows.Forms.Button
	$deleteTemplateButton.Text = "Delete Template"
	$deleteTemplateButton.Location = New-Object System.Drawing.Point(10,570)
	$deleteTemplateButton.Size = New-Object System.Drawing.Size(250,35)
	$deleteTemplateButton.Anchor = "Bottom,Left"

	$deleteTemplateButton.Add_Click({

		$selected = $list.SelectedItem

		if ($selected -eq $null) {
			$editorStatusLabel.Text = "Select a template to delete."
			$editorStatusTimer.Stop()
			$editorStatusTimer.Start()
			return
		}

		$confirm = [System.Windows.Forms.MessageBox]::Show(
			"!!! WARNING!!!`r`n`r`nThis action will permanently delete this template.`r`n`r`nThis action cannot be undone.`r`n`r`nAre you sure you want to delete?",
			"Delete Template",
			[System.Windows.Forms.MessageBoxButtons]::YesNo,
			[System.Windows.Forms.MessageBoxIcon]::Warning
		)

		if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
			return
		}

		$data = $templateConfig.PSObject.Properties[$selected].Value

		if ($data -ne $null -and -not [string]::IsNullOrWhiteSpace($data.file)) {
			$templatePath = Join-Path $templateFolder $data.file

			if (Test-Path $templatePath) {
				Remove-Item $templatePath -Force
			}
		}

		$templateConfig.PSObject.Properties.Remove($selected)

		$templateConfig |
			ConvertTo-Json -Depth 10 |
			Set-Content $templateConfigPath

		$list.Items.Remove($selected)

		$nameBox.Text = ""
		$fileBox.Text = ""
		$fieldsBox.Text = ""
		$contentBox.Text = ""

		$templateDropdown.Items.Clear()

		[void]$templateDropdown.Items.Add("")

		$templateConfig.PSObject.Properties.Name |
			Sort-Object |
			ForEach-Object {
				[void]$templateDropdown.Items.Add($_)
			}

		$templateDropdown.MaxDropDownItems = [Math]::Min($templateDropdown.Items.Count, 50)
		$templateDropdown.SelectedItem = $name

		$editorStatusLabel.Text = "Template deleted."

		$editorStatusTimer.Stop()
		$editorStatusTimer.Start()
	})

	$editor.Controls.Add($deleteTemplateButton)
	
	# =========================
	# OPEN TEMPLATE FOLDER BUTTON
	# =========================

	$openTemplateFolderButton = New-Object System.Windows.Forms.Button
	$openTemplateFolderButton.Text = "Open Folder"
	$openTemplateFolderButton.Location = New-Object System.Drawing.Point(10,615)
	$openTemplateFolderButton.Size = New-Object System.Drawing.Size(250,35)
	$openTemplateFolderButton.Anchor = "Bottom,Left"

	$openTemplateFolderButton.Add_Click({
		Ensure-TemplateStorageExists
		Start-Process explorer.exe $templateFolder
	})

	$editor.Controls.Add($openTemplateFolderButton)

    # =========================
	# NAME FIELD
	# =========================
	$nameLabel = New-Object System.Windows.Forms.Label
	$nameLabel.Text = "Template Name"
	$nameLabel.Location = New-Object System.Drawing.Point(280,10)
	$nameLabel.Size = New-Object System.Drawing.Size(250,25)
	$nameLabel.Anchor = "Top,Left"
	
	$editor.Controls.Add($nameLabel)
	
	$nameBox = New-Object System.Windows.Forms.TextBox
	$nameBox.Location = New-Object System.Drawing.Point(280,35)
	$nameBox.Size = New-Object System.Drawing.Size(580,30)
	$nameBox.Anchor = "Top,Left,Right"

	$editor.Controls.Add($nameBox)

	$nameBox.Add_TextChanged({

		$newName = $nameBox.Text.Trim()

		if ([string]::IsNullOrWhiteSpace($newName)) {
			return
		}

		$fileBox.Text = Convert-TemplateNameToFileName -name $newName

		# If user starts typing while nothing is selected, treat it like a new template
		if ($list.SelectedIndex -lt 0) {
			$script:isAddingNewTemplate = $true

			if (-not $list.Items.Contains($newName)) {
				[void]$list.Items.Add($newName)
			}

			$list.SelectedItem = $newName
			return
		}

		# If this is a new unsaved template, keep the list name updated live
		if ($script:isAddingNewTemplate -eq $true -and $list.SelectedIndex -ge 0) {
			$list.Items[$list.SelectedIndex] = $newName
		}
	})
	
	# =========================
	# FILE FIELD
	# =========================

	$fileLabel = New-Object System.Windows.Forms.Label
	$fileLabel.Text = "Template File"
	$fileLabel.Location = New-Object System.Drawing.Point(280,75)
	$fileLabel.Size = New-Object System.Drawing.Size(250,25)
	$fileLabel.Anchor = "Top,Left"

	$editor.Controls.Add($fileLabel)

	$fileBox = New-Object System.Windows.Forms.TextBox
	$fileBox.Location = New-Object System.Drawing.Point(280,100)
	$fileBox.Size = New-Object System.Drawing.Size(580,30)
	$fileBox.Anchor = "Top,Left,Right"

	# Read-only styling
	$fileBox.ReadOnly = $true
	$fileBox.BackColor = [System.Drawing.Color]::LightGray
	$fileBox.ForeColor = [System.Drawing.Color]::DimGray

	$editor.Controls.Add($fileBox)

	# =========================
	# FIELDS
	# =========================
	$fieldsLabel = New-Object System.Windows.Forms.Label
	$fieldsLabel.Text = "Input Fields"
	$fieldsLabel.Location = New-Object System.Drawing.Point(280,140)
	$fieldsLabel.Size = New-Object System.Drawing.Size(300,25)
	$fieldsLabel.Anchor = "Top,Left"

	$editor.Controls.Add($fieldsLabel)

	$fieldsBox = New-Object System.Windows.Forms.TextBox
	$fieldsBox.Location = New-Object System.Drawing.Point(280,165)
	$fieldsBox.Size = New-Object System.Drawing.Size(580,30)
	$fieldsBox.Anchor = "Top,Left,Right"
	
	$fieldsBox.ReadOnly = $true
	$fieldsBox.BackColor = [System.Drawing.Color]::LightGray
	$fieldsBox.ForeColor = [System.Drawing.Color]::DimGray

	$editor.Controls.Add($fieldsBox)

	# =========================
	# TEMPLATE CONTENT
	# =========================
	$contentLabel = New-Object System.Windows.Forms.Label
	$contentLabel.Text = "Template Content"
	$contentLabel.Location = New-Object System.Drawing.Point(280,214)
	$contentLabel.Size = New-Object System.Drawing.Size(300,25)
	$contentLabel.Anchor = "Top,Left"

	$editor.Controls.Add($contentLabel)
	
	# =========================
	# INSERT FIELD BUTTON
	# =========================
	$insertFieldButton = New-Object System.Windows.Forms.Button
	$insertFieldButton.Text = "Insert Input Field"
	$insertFieldButton.Location = New-Object System.Drawing.Point(700,205)
	$insertFieldButton.Size = New-Object System.Drawing.Size(160,30)
	$insertFieldButton.Anchor = "Top,Right"

	$insertFieldButton.Add_Click({
		Show-FieldInsertWindow -owner $editor -contentBox $contentBox -templateConfig $templateConfig
	})

	# =========================
	# TEMPLATE CONTENT CONT.
	# =========================
	$editor.Controls.Add($insertFieldButton)

	$contentBox = New-Object System.Windows.Forms.TextBox
	$contentBox.Location = New-Object System.Drawing.Point(280,245)
	$contentBox.Size = New-Object System.Drawing.Size(580,305)
	$contentBox.Multiline = $true
	$contentBox.ScrollBars = "Vertical"
	$contentBox.Anchor = "Top,Bottom,Left,Right"

	$editor.Controls.Add($contentBox)
		
		$contentBox.Add_TextChanged({

		$detectedFields = Get-TemplateFieldsFromContent -content $contentBox.Text

		$displayFields = $detectedFields | ForEach-Object {
			Convert-FieldNameForDisplay -fieldName $_
		}

		$fieldsBox.Text = ($displayFields -join ", ")
	})

    # =========================
    # SAVE BUTTON
    # =========================
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = "Save"
    $saveButton.Location = New-Object System.Drawing.Point(280,570)
	$saveButton.Anchor = "Bottom,Left"
    $saveButton.Size = New-Object System.Drawing.Size(120,40)
	$saveButton.Anchor = "Bottom,Left"

    $editor.Controls.Add($saveButton)
	
	# =========================
	# CLOSE BUTTON
	# =========================

	$closeButton = New-Object System.Windows.Forms.Button
	$closeButton.Text = "Close"
	$closeButton.Location = New-Object System.Drawing.Point(410,570)
	$closeButton.Size = New-Object System.Drawing.Size(120,40)
	$closeButton.Anchor = "Bottom,Left"

	$closeButton.Add_Click({
		$editor.Close()
	})

	$editor.Controls.Add($closeButton)
	
	# =========================
	# EDITOR STATUS LABEL
	# =========================

	$editorStatusLabel = New-Object System.Windows.Forms.Label
	$editorStatusLabel.Text = ""
	$editorStatusLabel.Location = New-Object System.Drawing.Point(550,580)
	$editorStatusLabel.Size = New-Object System.Drawing.Size(300,30)
	$editorStatusLabel.Anchor = "Bottom,Left"

	$editor.Controls.Add($editorStatusLabel)

	# =========================
	# EDITOR STATUS TIMER
	# =========================

	$editorStatusTimer = New-Object System.Windows.Forms.Timer
	$editorStatusTimer.Interval = 5000

	$editorStatusTimer.Add_Tick({

		param($sender, $eventArgs)

		if ($editorStatusLabel -ne $null) {
			$editorStatusLabel.Text = ""
		}

		$sender.Stop()
	})

    # =========================
    # LOAD SELECTED TEMPLATE
    # =========================
    $list.Add_SelectedIndexChanged({

		$selected = $list.SelectedItem

		if ($selected -eq $null) {
			return
		}

		# If this is a brand-new unsaved template, do not try to load from disk
		if ($selected -eq "Untitled Template" -and -not ($templateConfig.PSObject.Properties.Name -contains $selected)) {
			$nameBox.Text = "Untitled Template"
			$fileBox.Text = Convert-TemplateNameToFileName -name $nameBox.Text
			$fieldsBox.Text = ""
			$contentBox.Text = ""
			return
		}

		$data = $templateConfig.$selected

		if ($null -eq $data) {
			return
		}

		$nameBox.Text = $selected
		$fileBox.Text = $data.file
		$fieldsBox.Text = ($data.fields -join ", ")

		if ([string]::IsNullOrWhiteSpace($data.file)) {
			$contentBox.Text = ""
			return
		}

		$path = Join-Path $templateFolder $data.file

		if (Test-Path $path) {
			$contentBox.Text = Get-Content $path -Raw
		}
		else {
			$contentBox.Text = ""
		}
	})

    # =========================
    # SAVE LOGIC
    # =========================
    $saveButton.Add_Click({
		Ensure-TemplateStorageExists

		$name = $nameBox.Text.Trim()
		$file = $fileBox.Text.Trim()
		$fields = @(Get-TemplateFieldsFromContent -content $contentBox.Text | ForEach-Object {
			Convert-FieldNameForDisplay -fieldName $_
		})

		if ([string]::IsNullOrWhiteSpace($name)) {
			$editorStatusLabel.Text = "A template name must be provided."

			$editorStatusTimer.Stop()
			$editorStatusTimer.Start()

			return
		}

		if ([string]::IsNullOrWhiteSpace($file)) {
			$editorStatusLabel.Text = "A template file name could not be created."

			$editorStatusTimer.Stop()
			$editorStatusTimer.Start()

			return
		}

		$path = Join-Path $templateFolder $file

		# Save template text file
		Set-Content -Path $path -Value $contentBox.Text

		## Build a clean object
		$newTemplateObject = [PSCustomObject]@{
			file   = $file
			fields = @($fields)
		}

		# Add or update template in JSON config
		if ($templateConfig.PSObject.Properties.Name -contains $name) {
			$templateConfig.PSObject.Properties[$name].Value = $newTemplateObject
		}
		else {
			$templateConfig | Add-Member -MemberType NoteProperty -Name $name -Value $newTemplateObject
		}

		# Save JSON back to disk
		$templateConfig |
			ConvertTo-Json -Depth 10 |
			Set-Content $templateConfigPath
			
		$templateDropdown.Items.Clear()
		
		[void]$templateDropdown.Items.Add("")

		$templateConfig.PSObject.Properties.Name |
			Sort-Object |
			ForEach-Object {
				[void]$templateDropdown.Items.Add($_)
			}

		$templateDropdown.SelectedItem = $name
				
		$editorStatusLabel.Text = "Template saved."

		$editorStatusTimer.Stop()
		$editorStatusTimer.Start()
		
		$script:isAddingNewTemplate = $false

	})
	
	[void]$editor.ShowDialog($form)
}

[void]$form.ShowDialog()