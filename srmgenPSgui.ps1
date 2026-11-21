<#
.NAME
Steam ROM Manager - Manifest Generator & Editor GUI
.SYNOPSIS
A graphical user interface (WPF) for srm-generator to parse Windows shortcuts (.lnk)
and generate or edit Steam ROM Manager JSON manifests. Supports adaptive Light, Dark,
and Auto (System) theming with high-contrast, native Windows-compatible UI elements.
#>

# Ensure script runs in STA mode (required for WPF)
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    powershell.exe -STA -ExecutionPolicy Bypass -File $PSCommandPath @args
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Import core srmgen module
$modulePath = Join-Path $PSScriptRoot "srmgen.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Import-Module (Join-Path $PSScriptRoot "srmgen.psm1") -Force
}

# Define model class for DataGrid two-way binding
class SrmManifestItem {
    [string]$Title
    [string]$Target
    [string]$StartIn
    [string]$LaunchOptions
    [bool]$AppendArgsToExecutable
    [string]$Cover

    SrmManifestItem() {
        $this.Title = ""
        $this.Target = ""
        $this.StartIn = ""
        $this.LaunchOptions = ""
        $this.AppendArgsToExecutable = $false
        $this.Cover = ""
    }

    SrmManifestItem([string]$t, [string]$tgt, [string]$si, [string]$lo, [bool]$aa, [string]$cov) {
        $this.Title = $t
        $this.Target = $tgt
        $this.StartIn = $si
        $this.LaunchOptions = $lo
        $this.AppendArgsToExecutable = $aa
        $this.Cover = $cov
    }
}

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Steam ROM Manager - Manifest Generator &amp; Editor"
    Height="750" Width="1060"
    MinHeight="600" MinWidth="880"
    WindowStartupLocation="CenterScreen"
    Background="{DynamicResource BgWindow}"
    Foreground="{DynamicResource FgPrimary}"
    FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Theme Brushes (Default values; updated dynamically by Apply-Theme) -->
        <SolidColorBrush x:Key="BgWindow" Color="#18181f"/>
        <SolidColorBrush x:Key="BgCard" Color="#22222a"/>
        <SolidColorBrush x:Key="BgCardHeader" Color="#282834"/>
        <SolidColorBrush x:Key="BgInput" Color="#1b1b22"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#383848"/>
        <SolidColorBrush x:Key="BorderSubtle" Color="#2c2c3a"/>
        <SolidColorBrush x:Key="FgPrimary" Color="#f0f0f5"/>
        <SolidColorBrush x:Key="FgMuted" Color="#9a9aa8"/>
        <SolidColorBrush x:Key="BgGridRow" Color="#1e1e26"/>
        <SolidColorBrush x:Key="BgGridRowAlt" Color="#181820"/>
        <SolidColorBrush x:Key="BgGridHeader" Color="#262632"/>
        <SolidColorBrush x:Key="FgGridHeader" Color="#f0f0f5"/>
        <SolidColorBrush x:Key="BgGridLines" Color="#2c2c3a"/>
        <SolidColorBrush x:Key="BgSelection" Color="#2563eb"/>
        <SolidColorBrush x:Key="FgSelection" Color="#ffffff"/>
        <SolidColorBrush x:Key="BtnDefaultBg" Color="#2c2c38"/>
        <SolidColorBrush x:Key="BtnDefaultFg" Color="#f0f0f5"/>
        <SolidColorBrush x:Key="BtnPrimaryBg" Color="#1d5599"/>
        <SolidColorBrush x:Key="BtnPrimaryFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="BtnSuccessBg" Color="#238636"/>
        <SolidColorBrush x:Key="BtnSuccessFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="StatusBg" Color="#14141a"/>

        <!-- TextBlock Default Style -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>

        <!-- TextBox Default Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BgInput}"/>
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="CaretBrush" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="border"
                                CornerRadius="4"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}">
                            <ScrollViewer x:Name="PART_ContentHost" SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}" Margin="2,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BgSelection}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Button Default Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource BtnDefaultBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BtnDefaultFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                CornerRadius="4"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.75"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ComboBox Toggle Button Template -->
        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition />
                    <ColumnDefinition Width="22" />
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" CornerRadius="4"
                        Background="{DynamicResource BgInput}"
                        BorderBrush="{DynamicResource BorderBrush}"
                        BorderThickness="1" />
                <Path x:Name="Arrow" Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                      Data="M 0 0 L 4 4 L 8 0 Z" Fill="{DynamicResource FgPrimary}" />
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource BgSelection}"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <!-- ComboBoxItem Style -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="{DynamicResource BgInput}"/>
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Style.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BgSelection}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FgSelection}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BgInput}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Name="ToggleButton"
                                          Template="{StaticResource ComboBoxToggleButton}"
                                          Focusable="false"
                                          IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press"/>
                            <ContentPresenter Name="ContentSite"
                                              IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                              Margin="8,4,26,4"
                                              VerticalAlignment="Center"
                                              HorizontalAlignment="Left"/>
                            <Popup Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide">
                                <Grid Name="DropDown"
                                      SnapsToDevicePixels="True"
                                      MinWidth="{TemplateBinding ActualWidth}"
                                      MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder"
                                            Background="{DynamicResource BgInput}"
                                            BorderThickness="1"
                                            BorderBrush="{DynamicResource BorderBrush}"
                                            CornerRadius="4"
                                            Margin="0,2,0,4">
                                        <ScrollViewer Margin="2" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header Bar -->
        <Border Grid.Row="0" Margin="0,0,0,14" Padding="14,10" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="Steam ROM Manager - Manifest Generator" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBlock Text="Import Windows shortcuts (.lnk), customize launch properties, and export SRM manifests." FontSize="11" Foreground="{DynamicResource FgMuted}" Margin="0,2,0,0"/>
                </StackPanel>

                <!-- Theme Switcher (Auto / Dark / Light) -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,14,0">
                    <TextBlock Text="Theme:" VerticalAlignment="Center" Margin="0,0,6,0" Foreground="{DynamicResource FgMuted}" FontWeight="SemiBold"/>
                    <ComboBox Name="cmbTheme" Width="135">
                        <ComboBoxItem Content="⚙️ Auto (System)" IsSelected="True"/>
                        <ComboBoxItem Content="🌙 Dark Mode"/>
                        <ComboBoxItem Content="☀️ Light Mode"/>
                    </ComboBox>
                </StackPanel>

                <Button Name="btnLoadJson" Grid.Column="2" Content="📂 Open Existing Manifest" Background="{DynamicResource BtnPrimaryBg}" Foreground="{DynamicResource BtnPrimaryFg}" BorderBrush="{DynamicResource BorderBrush}" Padding="12,6" FontWeight="SemiBold"/>
            </Grid>
        </Border>

        <!-- Settings Card -->
        <Border Grid.Row="1" Margin="0,0,0,12" Padding="14" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Row 1: Source Shortcut Folder -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Shortcuts Source:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBox Name="txtInputPath" Grid.Column="1" Margin="0,0,8,0"/>
                    <Button Name="btnBrowseInput" Grid.Column="2" Content="Browse Folder..." Margin="0,0,8,0"/>
                    <Button Name="btnScan" Grid.Column="3" Content="⚡ Scan &amp; Load Shortcuts" Background="{DynamicResource BtnPrimaryBg}" Foreground="{DynamicResource BtnPrimaryFg}" BorderBrush="{DynamicResource BorderBrush}" FontWeight="SemiBold" Padding="14,5"/>
                </Grid>

                <!-- Row 2: Destination Output -->
                <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="140"/>
                        <ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Output Directory:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBox Name="txtOutputPath" Grid.Column="1" Margin="0,0,8,0"/>
                    <Button Name="btnBrowseOutput" Grid.Column="2" Content="Browse..." Margin="0,0,12,0"/>
                    <TextBlock Grid.Column="3" Text="Custom Filename:" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,8,0" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBox Name="txtOutputFile" Grid.Column="4"/>
                </Grid>

                <!-- Row 3: Output Mode, Template & Flags -->
                <Grid Grid.Row="2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="180"/>
                        <ColumnDefinition Width="90"/>
                        <ColumnDefinition Width="220"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Output Mode:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <ComboBox Name="cmbOutputMode" Grid.Column="1" Margin="0,0,12,0">
                        <ComboBoxItem Content="Merged (Single File)" IsSelected="True"/>
                        <ComboBoxItem Content="Individual (Per-Game Files)"/>
                    </ComboBox>

                    <TextBlock Grid.Column="2" Text="Template:" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,8,0" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <ComboBox Name="cmbTemplate" Grid.Column="3" Margin="0,0,16,0">
                        <ComboBoxItem Content="Default (Standard SRM)" IsSelected="True"/>
                        <ComboBoxItem Content="Artwork (With Grid Fields)"/>
                        <ComboBoxItem Content="Browse Custom Template..."/>
                    </ComboBox>

                    <StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">
                        <CheckBox Name="chkAppend" Content="Append to Existing" Margin="0,0,16,0"/>
                        <CheckBox Name="chkForce" Content="Overwrite (Force)" Margin="0,0,8,0"/>
                    </StackPanel>
                </Grid>
            </Grid>
        </Border>

        <!-- Data Grid & Table Actions -->
        <Border Grid.Row="2" Padding="12" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Action Toolbar -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Name="btnAddRow" Grid.Column="0" Content="+ Add Game" Margin="0,0,8,0"/>
                    <Button Name="btnRemoveRow" Grid.Column="1" Content="- Remove Selected" Margin="0,0,8,0"/>
                    <Button Name="btnClearAll" Grid.Column="2" Content="Clear Table" Margin="0,0,12,0"/>
                    <TextBlock Name="lblItemCount" Grid.Column="3" Text="0 games loaded" VerticalAlignment="Center" Foreground="{DynamicResource FgMuted}" FontWeight="SemiBold"/>

                    <Button Name="btnWhatIf" Grid.Column="5" Content="🔍 Simulate (WhatIf)" Margin="0,0,8,0" Padding="12,5"/>
                    <Button Name="btnExport" Grid.Column="6" Content="💾 Generate &amp; Save Manifest" Background="{DynamicResource BtnSuccessBg}" Foreground="{DynamicResource BtnSuccessFg}" BorderBrush="{DynamicResource BorderBrush}" FontWeight="SemiBold" Padding="16,5"/>
                </Grid>

                <!-- DataGrid -->
                <DataGrid
                    Name="gridEntries"
                    Grid.Row="1"
                    Background="{DynamicResource BgCard}"
                    Foreground="{DynamicResource FgPrimary}"
                    BorderBrush="{DynamicResource BorderBrush}"
                    BorderThickness="1"
                    RowBackground="{DynamicResource BgGridRow}"
                    AlternatingRowBackground="{DynamicResource BgGridRowAlt}"
                    HorizontalGridLinesBrush="{DynamicResource BgGridLines}"
                    VerticalGridLinesBrush="{DynamicResource BgGridLines}"
                    AutoGenerateColumns="False"
                    CanUserAddRows="True"
                    CanUserDeleteRows="True"
                    SelectionMode="Extended"
                    HeadersVisibility="Column"
                    FontSize="12">
                    <DataGrid.Resources>
                        <!-- Cell Editing TextBox Style: prevents white-on-white text during in-cell editing -->
                        <Style TargetType="TextBox">
                            <Setter Property="Background" Value="{DynamicResource BgInput}"/>
                            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
                            <Setter Property="CaretBrush" Value="{DynamicResource FgPrimary}"/>
                            <Setter Property="BorderThickness" Value="1"/>
                            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
                            <Setter Property="Padding" Value="4,2"/>
                        </Style>
                    </DataGrid.Resources>
                    <DataGrid.CellStyle>
                        <Style TargetType="DataGridCell">
                            <Setter Property="Background" Value="Transparent"/>
                            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
                            <Setter Property="BorderThickness" Value="0"/>
                            <Setter Property="Padding" Value="6,4"/>
                            <Style.Triggers>
                                <Trigger Property="IsSelected" Value="True">
                                    <Setter Property="Background" Value="{DynamicResource BgSelection}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource FgSelection}"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </DataGrid.CellStyle>
                    <DataGrid.ColumnHeaderStyle>
                        <Style TargetType="DataGridColumnHeader">
                            <Setter Property="Background" Value="{DynamicResource BgGridHeader}"/>
                            <Setter Property="Foreground" Value="{DynamicResource FgGridHeader}"/>
                            <Setter Property="FontWeight" Value="SemiBold"/>
                            <Setter Property="Padding" Value="8,6"/>
                            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
                            <Setter Property="BorderThickness" Value="0,0,1,1"/>
                        </Style>
                    </DataGrid.ColumnHeaderStyle>
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Title" Binding="{Binding Title}" Width="200"/>
                        <DataGridTextColumn Header="Target (Executable Path)" Binding="{Binding Target}" Width="280"/>
                        <DataGridTextColumn Header="Start In (Working Directory)" Binding="{Binding StartIn}" Width="220"/>
                        <DataGridTextColumn Header="Launch Options" Binding="{Binding LaunchOptions}" Width="150"/>
                        <DataGridCheckBoxColumn Header="Append Args" Binding="{Binding AppendArgsToExecutable}" Width="90"/>
                        <DataGridTextColumn Header="Cover / Artwork" Binding="{Binding Cover}" Width="120"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Grid>
        </Border>

        <!-- Bottom Status Bar -->
        <Border Grid.Row="3" Margin="0,10,0,0" Padding="8,5" Background="{DynamicResource StatusBg}" CornerRadius="4" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="txtStatus" Grid.Column="0" Text="Ready. Select a shortcut folder or open a manifest to begin." Foreground="{DynamicResource FgMuted}" FontSize="11"/>
                <TextBlock Grid.Column="1" Text="SRM Generator v1.1" Foreground="{DynamicResource FgMuted}" FontSize="10"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get Controls
$txtInputPath    = $window.FindName("txtInputPath")
$btnBrowseInput  = $window.FindName("btnBrowseInput")
$btnScan         = $window.FindName("btnScan")
$txtOutputPath   = $window.FindName("txtOutputPath")
$btnBrowseOutput = $window.FindName("btnBrowseOutput")
$txtOutputFile   = $window.FindName("txtOutputFile")
$cmbOutputMode   = $window.FindName("cmbOutputMode")
$cmbTemplate     = $window.FindName("cmbTemplate")
$chkAppend       = $window.FindName("chkAppend")
$chkForce        = $window.FindName("chkForce")
$btnLoadJson     = $window.FindName("btnLoadJson")
$btnAddRow       = $window.FindName("btnAddRow")
$btnRemoveRow    = $window.FindName("btnRemoveRow")
$btnClearAll     = $window.FindName("btnClearAll")
$lblItemCount    = $window.FindName("lblItemCount")
$btnWhatIf       = $window.FindName("btnWhatIf")
$btnExport       = $window.FindName("btnExport")
$gridEntries     = $window.FindName("gridEntries")
$txtStatus       = $window.FindName("txtStatus")
$cmbTheme        = $window.FindName("cmbTheme")

# Observable collection for DataGrid
$itemsCollection = [System.Collections.ObjectModel.ObservableCollection[SrmManifestItem]]::new()
$gridEntries.ItemsSource = $itemsCollection

$script:customTemplatePath = $null

# High-contrast, meticulously matched Dark and Light palettes
$script:ThemePalettes = @{
    Dark = @{
        BgWindow       = "#16161b"
        BgCard         = "#202028"
        BgCardHeader   = "#262632"
        BgInput        = "#181820"
        BorderBrush    = "#363644"
        BorderSubtle   = "#2a2a36"
        FgPrimary      = "#f2f2f7"
        FgMuted        = "#9c9ca8"
        BgGridRow      = "#1c1c24"
        BgGridRowAlt   = "#17171e"
        BgGridHeader   = "#252530"
        FgGridHeader   = "#f2f2f7"
        BgGridLines    = "#2c2c3a"
        BgSelection    = "#2563eb"
        FgSelection    = "#ffffff"
        BtnDefaultBg   = "#2a2a36"
        BtnDefaultFg   = "#f2f2f7"
        BtnPrimaryBg   = "#1d5599"
        BtnPrimaryFg   = "#ffffff"
        BtnSuccessBg   = "#238636"
        BtnSuccessFg   = "#ffffff"
        StatusBg       = "#131318"
    }
    Light = @{
        BgWindow       = "#f2f4f8"
        BgCard         = "#ffffff"
        BgCardHeader   = "#f7f9fa"
        BgInput        = "#ffffff"
        BorderBrush    = "#cfd4dc"
        BorderSubtle   = "#e1e4e8"
        FgPrimary      = "#1a1f26"
        FgMuted        = "#5b6574"
        BgGridRow      = "#ffffff"
        BgGridRowAlt   = "#f8f9fb"
        BgGridHeader   = "#e9edf2"
        FgGridHeader   = "#1a1f26"
        BgGridLines    = "#e2e6eb"
        BgSelection    = "#0969da"
        FgSelection    = "#ffffff"
        BtnDefaultBg   = "#eaedf2"
        BtnDefaultFg   = "#1a1f26"
        BtnPrimaryBg   = "#0969da"
        BtnPrimaryFg   = "#ffffff"
        BtnSuccessBg   = "#1a7f37"
        BtnSuccessFg   = "#ffffff"
        StatusBg       = "#e6eaf0"
    }
}

function Apply-Theme([string]$selectedMode) {
    $theme = "Dark"
    if ($selectedMode -like "*Light*") {
        $theme = "Light"
    } elseif ($selectedMode -like "*Dark*") {
        $theme = "Dark"
    } else {
        # Auto (System) - detect Windows registry preference
        try {
            $regVal = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop
            $theme = if ($regVal -ne 0) { "Light" } else { "Dark" }
        } catch {
            $theme = "Dark"
        }
    }

    $palette = $script:ThemePalettes[$theme]
    foreach ($key in $palette.Keys) {
        $colorHex = $palette[$key]
        $brush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($colorHex)
        $window.Resources[$key] = $brush
    }
}

function Update-Status([string]$message) {
    $txtStatus.Text = $message
}

function Update-ItemCount {
    $count = $itemsCollection.Count
    $lblItemCount.Text = "$count game(s) loaded"
}

# Theme selection event handler
$cmbTheme.Add_SelectionChanged({
    if ($cmbTheme.SelectedItem) {
        $choice = [string]$cmbTheme.SelectedItem.Content
        Apply-Theme $choice
        Update-Status "Applied theme: $choice"
    }
})

# Browse Input Folder
$btnBrowseInput.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Select a folder containing .lnk shortcuts"
    if (![string]::IsNullOrWhiteSpace($txtInputPath.Text) -and (Test-Path $txtInputPath.Text)) {
        $dialog.SelectedPath = $txtInputPath.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtInputPath.Text = $dialog.SelectedPath
        if ([string]::IsNullOrWhiteSpace($txtOutputPath.Text)) {
            $txtOutputPath.Text = $dialog.SelectedPath
        }
        Update-Status "Selected input folder: $($dialog.SelectedPath)"
    }
})

# Browse Output Folder
$btnBrowseOutput.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Select destination directory for manifest output"
    if (![string]::IsNullOrWhiteSpace($txtOutputPath.Text) -and (Test-Path $txtOutputPath.Text)) {
        $dialog.SelectedPath = $txtOutputPath.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutputPath.Text = $dialog.SelectedPath
        Update-Status "Selected output folder: $($dialog.SelectedPath)"
    }
})

# Template selection handler
$cmbTemplate.Add_SelectionChanged({
    $idx = $cmbTemplate.SelectedIndex
    if ($idx -eq 2) {
        # Custom template
        $dialog = [System.Windows.Forms.OpenFileDialog]::new()
        $dialog.Filter = "JSON Template (*.json)|*.json|All Files (*.*)|*.*"
        $dialog.Title = "Select Custom JSON Template"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:customTemplatePath = $dialog.FileName
            Update-Status "Custom template selected: $($dialog.FileName)"
        } else {
            $cmbTemplate.SelectedIndex = 0
        }
    } else {
        $script:customTemplatePath = $null
    }
})

# Scan & Parse Shortcuts
$btnScan.Add_Click({
    $inPath = $txtInputPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($inPath) -or !(Test-Path $inPath)) {
        [System.Windows.MessageBox]::Show("Please specify a valid shortcut folder or file path.", "Invalid Source", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Update-Status "Scanning shortcuts in $inPath..."

    $files = @()
    if (Test-Path $inPath -PathType Leaf) {
        if ($inPath -match '\.lnk$') { $files += Get-Item $inPath }
    } else {
        $files = @(Get-ChildItem -Path $inPath -Filter "*.lnk" -File)
    }

    if ($files.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No .lnk shortcuts were found in the selected folder.", "No Shortcuts Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        Update-Status "No shortcuts found."
        return
    }

    $templateName = if ($cmbTemplate.SelectedIndex -eq 1) { 'artwork' } elseif ($script:customTemplatePath) { $script:customTemplatePath } else { 'default' }
    $templateObj = Get-SrmTemplate -Template $templateName

    $itemsCollection.Clear()
    $parsedCount = 0

    foreach ($file in $files) {
        $sc = ConvertFrom-LnkShortcut -Path $file.FullName
        if ($null -eq $sc) { continue }

        $entry = New-SrmManifestEntry `
            -Title $sc.Title `
            -Target $sc.Target `
            -StartIn $sc.StartIn `
            -LaunchOptions $sc.LaunchOptions `
            -AppendArgsToExecutable $false `
            -Template $templateObj

        $cov = if ($entry.Contains('cover')) { [string]$entry['cover'] } else { "" }
        $item = [SrmManifestItem]::new($entry['title'], $entry['target'], $entry['startIn'], $entry['launchOptions'], [bool]$entry['appendArgsToExecutable'], $cov)
        $itemsCollection.Add($item)
        $parsedCount++
    }

    Update-ItemCount
    Update-Status "Successfully loaded $parsedCount shortcut(s)."
})

# Load Existing Manifest JSON
$btnLoadJson.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter = "Steam ROM Manager Manifest (*.json)|*.json|All Files (*.*)|*.*"
    $dialog.Title = "Open Existing SRM Manifest"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $jsonFile = $dialog.FileName
        $entries = Import-SrmManifest -Path $jsonFile

        $itemsCollection.Clear()
        foreach ($e in $entries) {
            $cov = if ($e.Contains('cover')) { [string]$e['cover'] } else { "" }
            $aa = if ($e.Contains('appendArgsToExecutable')) { [bool]$e['appendArgsToExecutable'] } else { $false }
            $item = [SrmManifestItem]::new([string]$e['title'], [string]$e['target'], [string]$e['startIn'], [string]$e['launchOptions'], $aa, $cov)
            $itemsCollection.Add($item)
        }

        $txtInputPath.Text = $jsonFile
        $txtOutputPath.Text = Split-Path $jsonFile -Parent
        $txtOutputFile.Text = Split-Path $jsonFile -Leaf

        Update-ItemCount
        Update-Status "Loaded $($entries.Count) entry/entries from $jsonFile."
    }
})

# Add Row
$btnAddRow.Add_Click({
    $newItem = [SrmManifestItem]::new("New Game", "C:\Path\to\game.exe", "C:\Path\to", "", $false, "")
    $itemsCollection.Add($newItem)
    Update-ItemCount
    $gridEntries.ScrollIntoView($newItem)
})

# Remove Selected Rows
$btnRemoveRow.Add_Click({
    $selected = @($gridEntries.SelectedItems)
    if ($selected.Count -eq 0) { return }
    foreach ($item in $selected) {
        [void]$itemsCollection.Remove($item)
    }
    Update-ItemCount
    Update-Status "Removed $($selected.Count) game(s)."
})

# Clear All
$btnClearAll.Add_Click({
    if ($itemsCollection.Count -gt 0) {
        if ([System.Windows.MessageBox]::Show("Clear all loaded entries from the table?", "Confirm Clear", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes) {
            $itemsCollection.Clear()
            Update-ItemCount
            Update-Status "Cleared all entries."
        }
    }
})

function Get-CurrentManifestEntries {
    $list = @()
    foreach ($item in $itemsCollection) {
        $entry = [ordered]@{
            title                  = $item.Title
            target                 = $item.Target
            startIn                = $item.StartIn
            launchOptions          = $item.LaunchOptions
            appendArgsToExecutable = $item.AppendArgsToExecutable
        }
        if (![string]::IsNullOrWhiteSpace($item.Cover)) {
            $entry['cover'] = $item.Cover
        }
        $list += $entry
    }
    return ,$list
}

# Simulate (WhatIf)
$btnWhatIf.Add_Click({
    if ($itemsCollection.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No games in the table to export.", "Empty Manifest", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    $outDir = $txtOutputPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($outDir)) {
        $outDir = (Get-Location).Path
    }

    $isIndividual = ($cmbOutputMode.SelectedIndex -eq 1)
    if ($isIndividual) {
        $msg = "Simulation (WhatIf):`n`nWill write $($itemsCollection.Count) individual manifest file(s) into:`n$outDir"
        [System.Windows.MessageBox]::Show($msg, "WhatIf Simulation", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } else {
        $outFile = $txtOutputFile.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($outFile)) {
            $inPath = $txtInputPath.Text.Trim()
            $outFile = if (![string]::IsNullOrWhiteSpace($inPath)) { Get-SrmDefaultManifestFileName -Path $inPath } else { "manifest.json" }
        }
        $fullPath = Join-Path $outDir $outFile
        $action = if ($chkAppend.IsChecked) { "Append entries to" } else { "Write/Overwrite" }
        $msg = "Simulation (WhatIf):`n`nAction: $action`nTarget Path: $fullPath`nTotal Games in table: $($itemsCollection.Count)"
        [System.Windows.MessageBox]::Show($msg, "WhatIf Simulation", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Export Manifest
$btnExport.Add_Click({
    if ($itemsCollection.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please load or add games to the table before exporting.", "Empty Table", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $outDir = $txtOutputPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($outDir)) {
        [System.Windows.MessageBox]::Show("Please specify an output directory.", "Missing Output Path", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    if (!(Test-Path $outDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Could not create output directory: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
    }

    $entries = Get-CurrentManifestEntries
    $isIndividual = ($cmbOutputMode.SelectedIndex -eq 1)
    $append = [bool]$chkAppend.IsChecked
    $force = [bool]$chkForce.IsChecked

    try {
        if ($isIndividual) {
            Export-SrmManifest -Manifests $entries -Path $outDir -OutputMode "Individual" -Append:$append -Force:$force
            Update-Status "Successfully generated $($entries.Count) individual manifest(s) in $outDir"
            
            $res = [System.Windows.MessageBox]::Show("Generated $($entries.Count) individual manifest(s) in:`n$outDir`n`nOpen folder in File Explorer?", "Export Successful", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                Start-Process "explorer.exe" $outDir
            }
        }
        else {
            $outFile = $txtOutputFile.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($outFile)) {
                $inPath = $txtInputPath.Text.Trim()
                $outFile = if (![string]::IsNullOrWhiteSpace($inPath)) { Get-SrmDefaultManifestFileName -Path $inPath } else { "manifest.json" }
            }
            $targetPath = Join-Path $outDir $outFile

            Export-SrmManifest -Manifests $entries -Path $targetPath -OutputMode "Merged" -Append:$append -Force:$force
            Update-Status "Successfully generated manifest: $targetPath"

            $res = [System.Windows.MessageBox]::Show("Manifest saved successfully!`n`nFile: $targetPath`n`nOpen folder in File Explorer?", "Export Successful", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                Start-Process "explorer.exe" ("/select,`"$targetPath`"")
            }
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Error exporting manifest: $_", "Export Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        Update-Status "Error: $_"
    }
})

# Auto-populate if default TEST folder exists
$defaultTestDir = Join-Path $PSScriptRoot "TEST"
if (Test-Path $defaultTestDir) {
    $txtInputPath.Text = $defaultTestDir
    $txtOutputPath.Text = $defaultTestDir
    $txtOutputFile.Text = Get-SrmDefaultManifestFileName -Path $defaultTestDir
}

# Apply default Auto (System) theme on startup
Apply-Theme "Auto"

# Show window
$window.ShowDialog() | Out-Null
