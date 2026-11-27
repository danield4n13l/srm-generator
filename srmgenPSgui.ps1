<#
.NAME
Steam ROM Manager - Manifest Generator & Editor GUI
.SYNOPSIS
A graphical user interface (WPF) for srm-generator to parse Windows shortcuts (.lnk)
across multiple folders, utilizing database hash caching, multi-threading, templates,
recent settings, progress tracking, and an integrated console/error log.
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
    [string]$Folder
    [string]$Title
    [string]$Target
    [string]$StartIn
    [string]$LaunchOptions
    [bool]$AppendArgsToExecutable
    [string]$Cover
    [string]$ItemHash
    [string]$SourceDirectory

    SrmManifestItem() {
        $this.Folder = ""
        $this.Title = ""
        $this.Target = ""
        $this.StartIn = ""
        $this.LaunchOptions = ""
        $this.AppendArgsToExecutable = $false
        $this.Cover = ""
        $this.ItemHash = ""
        $this.SourceDirectory = ""
    }

    SrmManifestItem([string]$fol, [string]$t, [string]$tgt, [string]$si, [string]$lo, [bool]$aa, [string]$cov, [string]$hash, [string]$srcDir) {
        $this.Folder = $fol
        $this.Title = $t
        $this.Target = $tgt
        $this.StartIn = $si
        $this.LaunchOptions = $lo
        $this.AppendArgsToExecutable = $aa
        $this.Cover = $cov
        $this.ItemHash = $hash
        $this.SourceDirectory = $srcDir
    }
}

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Steam ROM Manager - Manifest Generator &amp; Editor"
    Height="820" Width="1120"
    MinHeight="650" MinWidth="920"
    WindowStartupLocation="CenterScreen"
    Background="{DynamicResource BgWindow}"
    Foreground="{DynamicResource FgPrimary}"
    FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Theme Brushes (Default values; updated dynamically by Apply-Theme) -->
        <SolidColorBrush x:Key="BgWindow" Color="#16161b"/>
        <SolidColorBrush x:Key="BgCard" Color="#202028"/>
        <SolidColorBrush x:Key="BgCardHeader" Color="#262632"/>
        <SolidColorBrush x:Key="BgInput" Color="#181820"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#363644"/>
        <SolidColorBrush x:Key="BorderSubtle" Color="#2a2a36"/>
        <SolidColorBrush x:Key="FgPrimary" Color="#f2f2f7"/>
        <SolidColorBrush x:Key="FgMuted" Color="#9c9ca8"/>
        <SolidColorBrush x:Key="BgGridRow" Color="#1c1c24"/>
        <SolidColorBrush x:Key="BgGridRowAlt" Color="#17171e"/>
        <SolidColorBrush x:Key="BgGridHeader" Color="#252530"/>
        <SolidColorBrush x:Key="FgGridHeader" Color="#f2f2f7"/>
        <SolidColorBrush x:Key="BgGridLines" Color="#2c2c3a"/>
        <SolidColorBrush x:Key="BgSelection" Color="#2563eb"/>
        <SolidColorBrush x:Key="FgSelection" Color="#ffffff"/>
        <SolidColorBrush x:Key="BtnDefaultBg" Color="#2a2a36"/>
        <SolidColorBrush x:Key="BtnDefaultFg" Color="#f2f2f7"/>
        <SolidColorBrush x:Key="BtnPrimaryBg" Color="#1d5599"/>
        <SolidColorBrush x:Key="BtnPrimaryFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="BtnSuccessBg" Color="#238636"/>
        <SolidColorBrush x:Key="BtnSuccessFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="StatusBg" Color="#131318"/>

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

        <!-- ListBox Default Style -->
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="{DynamicResource BgInput}"/>
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>

        <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="6,3"/>
            <Setter Property="Foreground" Value="{DynamicResource FgPrimary}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BgSelection}"/>
                    <Setter Property="Foreground" Value="{DynamicResource FgSelection}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Button Default Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource BtnDefaultBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BtnDefaultFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,5"/>
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

    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Header -->
            <RowDefinition Height="Auto"/> <!-- Source Folders & Config -->
            <RowDefinition Height="*"/>    <!-- DataGrid -->
            <RowDefinition Height="Auto"/> <!-- Progress & Console Log -->
            <RowDefinition Height="Auto"/> <!-- Status Bar -->
        </Grid.RowDefinitions>

        <!-- Header Bar -->
        <Border Grid.Row="0" Margin="0,0,0,10" Padding="12,8" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="Steam ROM Manager - Manifest Generator" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBlock Text="Multi-threaded batch shortcut parser, database hash cache, and manifest generator." FontSize="11" Foreground="{DynamicResource FgMuted}" Margin="0,1,0,0"/>
                </StackPanel>

                <!-- Theme Switcher -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
                    <TextBlock Text="Theme:" VerticalAlignment="Center" Margin="0,0,6,0" Foreground="{DynamicResource FgMuted}" FontWeight="SemiBold"/>
                    <ComboBox Name="cmbTheme" Width="130">
                        <ComboBoxItem Content="⚙️ Auto (System)" IsSelected="True"/>
                        <ComboBoxItem Content="🌙 Dark Mode"/>
                        <ComboBoxItem Content="☀️ Light Mode"/>
                    </ComboBox>
                </StackPanel>

                <Button Name="btnSaveCustomTemplate" Grid.Column="2" Content="💾 Save Template" Margin="0,0,8,0" Padding="10,5"/>
                <Button Name="btnLoadJson" Grid.Column="3" Content="📂 Open Manifest" Background="{DynamicResource BtnPrimaryBg}" Foreground="{DynamicResource BtnPrimaryFg}" BorderBrush="{DynamicResource BorderBrush}" Padding="10,5" FontWeight="SemiBold"/>
            </Grid>
        </Border>

        <!-- Source Folders & Settings Card -->
        <Border Grid.Row="1" Margin="0,0,0,10" Padding="12" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Row 1: Multi-Folder Source Selection -->
                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" VerticalAlignment="Top">
                        <TextBlock Text="Source Folders:" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                        <TextBlock Text="Shortcut directories" FontSize="10" Foreground="{DynamicResource FgMuted}"/>
                    </StackPanel>
                    
                    <ListBox Name="lstFolders" Grid.Column="1" Height="68" Margin="0,0,8,0"/>

                    <StackPanel Grid.Column="2" VerticalAlignment="Top">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                            <Button Name="btnAddFolder" Content="➕ Add Folder..." Margin="0,0,6,0" Padding="8,4"/>
                            <Button Name="btnRemoveFolder" Content="➖ Remove" Margin="0,0,6,0" Padding="8,4"/>
                            <Button Name="btnClearFolders" Content="Clear" Padding="8,4"/>
                        </StackPanel>
                        <ComboBox Name="cmbRecentFolders" Width="220" Margin="0,2,0,0" Padding="6,3">
                            <ComboBoxItem Content="Recent Folders..." IsSelected="True"/>
                        </ComboBox>
                    </StackPanel>
                </Grid>

                <!-- Row 2: Destination Output & Modes -->
                <Grid Grid.Row="1" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="120"/>
                        <ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Output Folder:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBox Name="txtOutputPath" Grid.Column="1" Margin="0,0,8,0"/>
                    <Button Name="btnBrowseOutput" Grid.Column="2" Content="Browse..." Margin="0,0,12,0"/>
                    <TextBlock Grid.Column="3" Text="Output Filename:" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,6,0" Foreground="{DynamicResource FgPrimary}"/>
                    <TextBox Name="txtOutputFile" Grid.Column="4"/>
                </Grid>

                <!-- Row 3: Output Mode, Template, Threads & Flags -->
                <Grid Grid.Row="2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="130"/>
                        <ColumnDefinition Width="210"/>
                        <ColumnDefinition Width="80"/>
                        <ColumnDefinition Width="180"/>
                        <ColumnDefinition Width="65"/>
                        <ColumnDefinition Width="65"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Output Mode:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <ComboBox Name="cmbOutputMode" Grid.Column="1" Margin="0,0,10,0">
                        <ComboBoxItem Content="Per Folder (Collated Manifest)" IsSelected="True"/>
                        <ComboBoxItem Content="Per Game (Individual Manifests)"/>
                        <ComboBoxItem Content="Single Merged File (All Games)"/>
                    </ComboBox>

                    <TextBlock Grid.Column="2" Text="Template:" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,6,0" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <ComboBox Name="cmbTemplate" Grid.Column="3" Margin="0,0,10,0">
                        <ComboBoxItem Content="Default (Standard SRM)" IsSelected="True"/>
                        <ComboBoxItem Content="Artwork (With Grid Fields)"/>
                        <ComboBoxItem Content="Browse Custom Template..."/>
                    </ComboBox>

                    <TextBlock Grid.Column="4" Text="Threads:" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,4,0" FontWeight="SemiBold" Foreground="{DynamicResource FgPrimary}"/>
                    <ComboBox Name="cmbThreads" Grid.Column="5" Margin="0,0,12,0">
                        <ComboBoxItem Content="1"/>
                        <ComboBoxItem Content="2"/>
                        <ComboBoxItem Content="4" IsSelected="True"/>
                        <ComboBoxItem Content="8"/>
                        <ComboBoxItem Content="16"/>
                    </ComboBox>

                    <StackPanel Grid.Column="6" Orientation="Horizontal" VerticalAlignment="Center">
                        <CheckBox Name="chkSkipUnmodified" Content="⚡ Skip Unmodified (Cache)" Margin="0,0,12,0" IsChecked="True"/>
                        <CheckBox Name="chkAppend" Content="Append" Margin="0,0,12,0"/>
                        <CheckBox Name="chkForce" Content="Force Overwrite"/>
                    </StackPanel>
                </Grid>
            </Grid>
        </Border>

        <!-- Data Grid Card -->
        <Border Grid.Row="2" Padding="10" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Action Toolbar -->
                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Name="btnAddRow" Grid.Column="0" Content="+ Add Game" Margin="0,0,6,0"/>
                    <Button Name="btnRemoveRow" Grid.Column="1" Content="- Remove Selected" Margin="0,0,6,0"/>
                    <Button Name="btnClearAll" Grid.Column="2" Content="Clear Table" Margin="0,0,10,0"/>
                    <TextBlock Name="lblItemCount" Grid.Column="3" Text="0 game(s) loaded" VerticalAlignment="Center" Foreground="{DynamicResource FgMuted}" FontWeight="SemiBold"/>

                    <Button Name="btnScan" Grid.Column="5" Content="⚡ Scan Shortcuts" Background="{DynamicResource BtnPrimaryBg}" Foreground="{DynamicResource BtnPrimaryFg}" BorderBrush="{DynamicResource BorderBrush}" FontWeight="SemiBold" Margin="0,0,8,0" Padding="14,5"/>
                    <Button Name="btnWhatIf" Grid.Column="6" Content="🔍 Simulate (WhatIf)" Margin="0,0,8,0" Padding="10,5"/>
                    <Button Name="btnExport" Grid.Column="7" Content="💾 Export Manifest(s)" Background="{DynamicResource BtnSuccessBg}" Foreground="{DynamicResource BtnSuccessFg}" BorderBrush="{DynamicResource BorderBrush}" FontWeight="SemiBold" Padding="16,5"/>
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
                        <DataGridTextColumn Header="Folder" Binding="{Binding Folder}" Width="110" IsReadOnly="True"/>
                        <DataGridTextColumn Header="Title" Binding="{Binding Title}" Width="190"/>
                        <DataGridTextColumn Header="Target (Executable Path)" Binding="{Binding Target}" Width="260"/>
                        <DataGridTextColumn Header="Start In (Working Directory)" Binding="{Binding StartIn}" Width="190"/>
                        <DataGridTextColumn Header="Launch Options" Binding="{Binding LaunchOptions}" Width="130"/>
                        <DataGridCheckBoxColumn Header="Append Args" Binding="{Binding AppendArgsToExecutable}" Width="85"/>
                        <DataGridTextColumn Header="Cover / Artwork" Binding="{Binding Cover}" Width="110"/>
                        <DataGridTextColumn Header="Hash" Binding="{Binding ItemHash}" Width="90" IsReadOnly="True"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Grid>
        </Border>

        <!-- Progress Bar & Console / Error Log Card -->
        <Border Grid.Row="3" Margin="0,8,0,0" Padding="10,8" Background="{DynamicResource BgCard}" CornerRadius="6" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Progress Bar Row -->
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <ProgressBar Name="pbScan" Height="14" Minimum="0" Maximum="100" Value="0" Background="{DynamicResource BgInput}" BorderBrush="{DynamicResource BorderBrush}" Foreground="{DynamicResource BgSelection}"/>
                    <TextBlock Name="lblProgress" Grid.Column="1" Text="Idle" Margin="8,0,0,0" FontSize="11" Foreground="{DynamicResource FgMuted}" FontWeight="SemiBold"/>
                </Grid>

                <!-- Console Log Header & Controls -->
                <Grid Grid.Row="1" Margin="0,2,0,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="Console &amp; Error Activity Log:" FontWeight="SemiBold" FontSize="11" Foreground="{DynamicResource FgMuted}"/>
                    <Button Name="btnCopyLog" Grid.Column="1" Content="📋 Copy Log" Margin="0,0,6,0" Padding="8,2" FontSize="11"/>
                    <Button Name="btnClearLog" Grid.Column="2" Content="🗑️ Clear Log" Padding="8,2" FontSize="11"/>
                </Grid>

                <!-- Console Log Scrollable Box -->
                <TextBox Name="txtConsoleLog" Grid.Row="2" Height="85" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                         FontFamily="Consolas" FontSize="11" Background="{DynamicResource StatusBg}" Foreground="{DynamicResource FgPrimary}" BorderBrush="{DynamicResource BorderSubtle}"/>
            </Grid>
        </Border>

        <!-- Bottom Status Bar -->
        <Border Grid.Row="4" Margin="0,6,0,0" Padding="8,4" Background="{DynamicResource StatusBg}" CornerRadius="4" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="txtStatus" Grid.Column="0" Text="Ready." Foreground="{DynamicResource FgMuted}" FontSize="11"/>
                <TextBlock Grid.Column="1" Text="SRM Generator v1.2" Foreground="{DynamicResource FgMuted}" FontSize="10"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get Controls
$lstFolders             = $window.FindName("lstFolders")
$btnAddFolder           = $window.FindName("btnAddFolder")
$btnRemoveFolder        = $window.FindName("btnRemoveFolder")
$btnClearFolders        = $window.FindName("btnClearFolders")
$cmbRecentFolders       = $window.FindName("cmbRecentFolders")
$txtOutputPath          = $window.FindName("txtOutputPath")
$btnBrowseOutput        = $window.FindName("btnBrowseOutput")
$txtOutputFile          = $window.FindName("txtOutputFile")
$cmbOutputMode          = $window.FindName("cmbOutputMode")
$cmbTemplate            = $window.FindName("cmbTemplate")
$cmbThreads             = $window.FindName("cmbThreads")
$chkSkipUnmodified      = $window.FindName("chkSkipUnmodified")
$chkAppend              = $window.FindName("chkAppend")
$chkForce               = $window.FindName("chkForce")
$btnLoadJson            = $window.FindName("btnLoadJson")
$btnSaveCustomTemplate  = $window.FindName("btnSaveCustomTemplate")
$btnAddRow              = $window.FindName("btnAddRow")
$btnRemoveRow           = $window.FindName("btnRemoveRow")
$btnClearAll            = $window.FindName("btnClearAll")
$lblItemCount           = $window.FindName("lblItemCount")
$btnScan                = $window.FindName("btnScan")
$btnWhatIf              = $window.FindName("btnWhatIf")
$btnExport              = $window.FindName("btnExport")
$gridEntries            = $window.FindName("gridEntries")
$pbScan                 = $window.FindName("pbScan")
$lblProgress            = $window.FindName("lblProgress")
$btnCopyLog             = $window.FindName("btnCopyLog")
$btnClearLog            = $window.FindName("btnClearLog")
$txtConsoleLog          = $window.FindName("txtConsoleLog")
$txtStatus              = $window.FindName("txtStatus")
$cmbTheme               = $window.FindName("cmbTheme")

# Observable collections
$itemsCollection = [System.Collections.ObjectModel.ObservableCollection[SrmManifestItem]]::new()
$gridEntries.ItemsSource = $itemsCollection

# State
$script:customTemplatePath = $null
$script:settings = Get-SrmSettings
$script:database = Get-SrmDatabase

# High-contrast Dark and Light theme palettes
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

function Write-GuiLog([string]$level, [string]$message) {
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $logLine = "[$timestamp] [$level] $message"
    $window.Dispatcher.Invoke([Action]{
        $txtConsoleLog.AppendText("$logLine`r`n")
        $txtConsoleLog.ScrollToEnd()
    })
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
        Write-GuiLog "INFO" "Applied theme: $choice"
    }
})

# Log controls
$btnCopyLog.Add_Click({
    if (![string]::IsNullOrEmpty($txtConsoleLog.Text)) {
        [System.Windows.Clipboard]::SetText($txtConsoleLog.Text)
        Update-Status "Console log copied to clipboard."
    }
})

$btnClearLog.Add_Click({
    $txtConsoleLog.Clear()
    Update-Status "Console log cleared."
})

# Folder management
$btnAddFolder.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Select a folder containing .lnk shortcuts"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $path = $dialog.SelectedPath
        if (-not $lstFolders.Items.Contains($path)) {
            [void]$lstFolders.Items.Add($path)
            Write-GuiLog "INFO" "Added source folder: $path"
            if ([string]::IsNullOrWhiteSpace($txtOutputPath.Text)) {
                $txtOutputPath.Text = $path
            }
        }
    }
})

$btnRemoveFolder.Add_Click({
    $selected = $lstFolders.SelectedItem
    if ($null -ne $selected) {
        $lstFolders.Items.Remove($selected)
        Write-GuiLog "INFO" "Removed source folder: $selected"
    }
})

$btnClearFolders.Add_Click({
    $lstFolders.Items.Clear()
    Write-GuiLog "INFO" "Cleared all source folders."
})

$cmbRecentFolders.Add_SelectionChanged({
    if ($cmbRecentFolders.SelectedIndex -gt 0) {
        $folder = [string]$cmbRecentFolders.SelectedItem
        if (![string]::IsNullOrWhiteSpace($folder) -and (Test-Path $folder) -and -not $lstFolders.Items.Contains($folder)) {
            [void]$lstFolders.Items.Add($folder)
            Write-GuiLog "INFO" "Added recent folder: $folder"
            if ([string]::IsNullOrWhiteSpace($txtOutputPath.Text)) {
                $txtOutputPath.Text = $folder
            }
        }
        $cmbRecentFolders.SelectedIndex = 0
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
        Write-GuiLog "INFO" "Selected output folder: $($dialog.SelectedPath)"
    }
})

# Template selection handler
$cmbTemplate.Add_SelectionChanged({
    $idx = $cmbTemplate.SelectedIndex
    if ($idx -eq 2) {
        $dialog = [System.Windows.Forms.OpenFileDialog]::new()
        $dialog.Filter = "JSON Template (*.json)|*.json|All Files (*.*)|*.*"
        $dialog.Title = "Select Custom JSON Template"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:customTemplatePath = $dialog.FileName
            Write-GuiLog "INFO" "Loaded custom template: $($dialog.FileName)"
        } else {
            $cmbTemplate.SelectedIndex = 0
        }
    } else {
        $script:customTemplatePath = $null
    }
})

# Save current custom template
$btnSaveCustomTemplate.Add_Click({
    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Filter = "JSON Template (*.json)|*.json"
    $dialog.Title = "Save Current Template Preset"
    $dialog.FileName = "custom.template.json"
    $templatesDir = Join-Path $PSScriptRoot "templates"
    if (Test-Path $templatesDir) { $dialog.InitialDirectory = $templatesDir }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $tpl = [ordered]@{
            title                  = "{{title}}"
            target                 = "{{target}}"
            startIn                = "{{startIn}}"
            launchOptions          = "{{launchOptions}}"
            appendArgsToExecutable = $false
            cover                  = ""
        }
        $tpl | ConvertTo-Json -Depth 5 | Set-Content -Path $dialog.FileName -Encoding UTF8
        Write-GuiLog "SUCCESS" "Template preset saved: $($dialog.FileName)"
        [System.Windows.MessageBox]::Show("Template saved successfully to:`n$($dialog.FileName)", "Template Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Scan & Parse Shortcuts (Threaded)
$btnScan.Add_Click({
    if ($lstFolders.Items.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please add at least one folder containing .lnk shortcuts.", "No Source Folders", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $folderPaths = @($lstFolders.Items)
    $threadCount = [int]$cmbThreads.Text
    if ($threadCount -le 0) { $threadCount = 4 }
    $skipUnmod = [bool]$chkSkipUnmodified.IsChecked

    $templateName = if ($cmbTemplate.SelectedIndex -eq 1) { 'artwork' } elseif ($script:customTemplatePath) { $script:customTemplatePath } else { 'default' }
    $templateObj = Get-SrmTemplate -Template $templateName

    # UI setup for scan
    $btnScan.IsEnabled = $false
    $btnExport.IsEnabled = $false
    $pbScan.Value = 0
    $lblProgress.Text = "Scanning folders..."
    Update-Status "Starting parallel scan across $($folderPaths.Count) folder(s)..."
    Write-GuiLog "INFO" "Starting scan across $($folderPaths.Count) folder(s) ($threadCount threads, SkipUnmodified: $skipUnmod)..."

    $onProgress = {
        param($curr, $tot, $file, $status)
        $window.Dispatcher.Invoke([Action]{
            $pct = if ($tot -gt 0) { [int](($curr / $tot) * 100) } else { 0 }
            $pbScan.Value = $pct
            $lblProgress.Text = "$status ($curr/$tot)"
        })
    }

    $onLog = {
        param($lvl, $msg)
        Write-GuiLog $lvl $msg
    }

    try {
        $entries = Invoke-SrmParallelScan `
            -InputPaths $folderPaths `
            -Database $script:database `
            -Template $templateObj `
            -SkipUnmodified:$skipUnmod `
            -ThreadCount $threadCount `
            -OnProgress $onProgress `
            -OnLog $onLog

        $itemsCollection.Clear()
        foreach ($e in $entries) {
            $fol = if ($e.Contains('_SourceDirectory') -and !([string]::IsNullOrWhiteSpace($e['_SourceDirectory']))) { Split-Path $e['_SourceDirectory'] -Leaf } else { "" }
            $cov = if ($e.Contains('cover')) { [string]$e['cover'] } else { "" }
            $hash = if ($e.Contains('_ItemHash')) { [string]$e['_ItemHash'] } else { "" }
            $srcDir = if ($e.Contains('_SourceDirectory')) { [string]$e['_SourceDirectory'] } else { "" }
            $aa = if ($e.Contains('appendArgsToExecutable')) { [bool]$e['appendArgsToExecutable'] } else { $false }

            $item = [SrmManifestItem]::new($fol, [string]$e['title'], [string]$e['target'], [string]$e['startIn'], [string]$e['launchOptions'], $aa, $cov, $hash, $srcDir)
            $itemsCollection.Add($item)
        }

        # Save database cache & update settings
        Save-SrmDatabase -Database $script:database
        Write-GuiLog "SUCCESS" "Database updated with $($script:database.Shortcuts.Count) total shortcut record(s)."

        $recentList = @($folderPaths) + @($script:settings.RecentInputFolders | Where-Object { $folderPaths -notcontains $_ })
        $script:settings.RecentInputFolders = @($recentList | Select-Object -First 15)
        $script:settings.LastOutputPath     = $txtOutputPath.Text
        $script:settings.LastOutputMode     = switch ($cmbOutputMode.SelectedIndex) { 1 { 'PerGame' }; 2 { 'Merged' }; default { 'PerFolder' } }
        $script:settings.SkipUnmodified     = $skipUnmod
        Save-SrmSettings -Settings $script:settings

        Update-ItemCount
        $pbScan.Value = 100
        $lblProgress.Text = "Ready ($($itemsCollection.Count) games)"
        Update-Status "Scan completed. Loaded $($itemsCollection.Count) game(s)."
    }
    catch {
        Write-GuiLog "ERROR" "Scan failed: $_"
        [System.Windows.MessageBox]::Show("Error during scan: $_", "Scan Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    finally {
        $btnScan.IsEnabled = $true
        $btnExport.IsEnabled = $true
    }
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
            $hash = Get-SrmItemHash -Target ([string]$e['target']) -StartIn ([string]$e['startIn'])

            $item = [SrmManifestItem]::new("Imported", [string]$e['title'], [string]$e['target'], [string]$e['startIn'], [string]$e['launchOptions'], $aa, $cov, $hash, (Split-Path $jsonFile -Parent))
            $itemsCollection.Add($item)
        }

        $txtOutputPath.Text = Split-Path $jsonFile -Parent
        $txtOutputFile.Text = Split-Path $jsonFile -Leaf
        $cmbOutputMode.SelectedIndex = 2 # Single Merged

        Update-ItemCount
        Write-GuiLog "SUCCESS" "Imported $($entries.Count) entry/entries from $jsonFile"
        Update-Status "Loaded $($entries.Count) entries from $jsonFile."
    }
})

# Add Row
$btnAddRow.Add_Click({
    $newItem = [SrmManifestItem]::new("Custom", "New Game", "C:\Path\to\game.exe", "C:\Path\to", "", $false, "", "", "")
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
    Write-GuiLog "INFO" "Removed $($selected.Count) game(s) from table."
})

# Clear All
$btnClearAll.Add_Click({
    if ($itemsCollection.Count -gt 0) {
        if ([System.Windows.MessageBox]::Show("Clear all loaded entries from the table?", "Confirm Clear", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes) {
            $itemsCollection.Clear()
            Update-ItemCount
            Write-GuiLog "INFO" "Cleared table."
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
        if (![string]::IsNullOrWhiteSpace($item.SourceDirectory)) {
            $entry['_SourceDirectory'] = $item.SourceDirectory
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
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = (Get-Location).Path }
    $mode = switch ($cmbOutputMode.SelectedIndex) { 1 { 'PerGame' }; 2 { 'Merged' }; default { 'PerFolder' } }

    $msg = "Simulation (WhatIf):`n`nTotal Games in table: $($itemsCollection.Count)`nOutput Mode: $mode`nDestination Directory: $outDir`n`n"
    if ($mode -eq 'PerFolder') {
        $groups = $itemsCollection | Group-Object -Property Folder
        $msg += "Will generate $($groups.Count) collated manifest file(s):`n"
        foreach ($g in $groups) {
            $msg += "  - $($g.Name).manifest.json ($($g.Count) games)`n"
        }
    } elseif ($mode -eq 'PerGame') {
        $msg += "Will generate $($itemsCollection.Count) individual manifest file(s) (one per game)."
    } else {
        $outFile = if (![string]::IsNullOrWhiteSpace($txtOutputFile.Text)) { $txtOutputFile.Text } else { "manifest.json" }
        $msg += "Will generate single merged manifest: $(Join-Path $outDir $outFile)"
    }

    [System.Windows.MessageBox]::Show($msg, "WhatIf Simulation", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    Write-GuiLog "INFO" "Ran WhatIf simulation for $mode mode."
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
    $outputMode = switch ($cmbOutputMode.SelectedIndex) { 1 { 'PerGame' }; 2 { 'Merged' }; default { 'PerFolder' } }
    $append = [bool]$chkAppend.IsChecked
    $force = [bool]$chkForce.IsChecked

    $targetPath = if ($outputMode -eq 'Merged') {
        $fName = if (![string]::IsNullOrWhiteSpace($txtOutputFile.Text)) { $txtOutputFile.Text } else { "manifest.json" }
        Join-Path $outDir $fName
    } else {
        $outDir
    }

    try {
        Write-GuiLog "INFO" "Exporting $($entries.Count) entries in $outputMode mode to: $targetPath"
        $writtenFiles = Export-SrmManifest `
            -Manifests $entries `
            -Path $targetPath `
            -OutputMode $outputMode `
            -Append:$append `
            -Force:$force `
            -PassThru:$true

        Write-GuiLog "SUCCESS" "Successfully exported $($writtenFiles.Count) manifest file(s)."
        Update-Status "Export completed successfully. ($($writtenFiles.Count) files created/updated)"

        $res = [System.Windows.MessageBox]::Show("Manifest export completed successfully!`n`nGenerated $($writtenFiles.Count) file(s) in:`n$outDir`n`nOpen folder in File Explorer?", "Export Successful", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            Start-Process "explorer.exe" $outDir
        }
    }
    catch {
        Write-GuiLog "ERROR" "Export failed: $_"
        [System.Windows.MessageBox]::Show("Error exporting manifest: $_", "Export Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        Update-Status "Error: $_"
    }
})

# Load settings & populate UI on startup
if ($script:settings.RecentInputFolders) {
    foreach ($rf in $script:settings.RecentInputFolders) {
        if (![string]::IsNullOrWhiteSpace($rf) -and (Test-Path $rf)) {
            [void]$cmbRecentFolders.Items.Add($rf)
        }
    }
}

if (![string]::IsNullOrWhiteSpace($script:settings.LastOutputPath) -and (Test-Path $script:settings.LastOutputPath)) {
    $txtOutputPath.Text = $script:settings.LastOutputPath
}

if ($script:settings.LastOutputMode) {
    switch ($script:settings.LastOutputMode) {
        'PerGame'   { $cmbOutputMode.SelectedIndex = 1 }
        'Merged'    { $cmbOutputMode.SelectedIndex = 2 }
        default     { $cmbOutputMode.SelectedIndex = 0 }
    }
}

$chkSkipUnmodified.IsChecked = [bool]$script:settings.SkipUnmodified

# Pre-populate TEST folder if present
$defaultTestDir = Join-Path $PSScriptRoot "TEST"
if (Test-Path $defaultTestDir) {
    [void]$lstFolders.Items.Add($defaultTestDir)
    if ([string]::IsNullOrWhiteSpace($txtOutputPath.Text)) {
        $txtOutputPath.Text = $defaultTestDir
    }
}

# Apply default Auto (System) theme on startup
Apply-Theme "Auto"

Write-GuiLog "INFO" "SRM Generator GUI initialized. Database contains $($script:database.Shortcuts.Count) cached shortcut(s)."

# Show window
$window.ShowDialog() | Out-Null
