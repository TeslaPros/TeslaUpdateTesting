# Tesla SS Tools - isolated cinematic startup prototype
# This file is intentionally standalone and does not modify the production app.

$ErrorActionPreference = 'Stop'

$script:EntryPath = if ($PSCommandPath) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    $null
}

function Restart-InStaMode {
    param([Parameter(Mandatory = $true)][string]$Path)

    $quotedPath = '"' + $Path.Replace('"', '\"') + '"'
    $arguments = @(
        '-NoProfile'
        '-STA'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $quotedPath
    )

    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    if (-not $script:EntryPath) {
        throw 'The prototype needs STA mode, but the script path could not be resolved.'
    }

    Restart-InStaMode -Path $script:EntryPath
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class TeslaStartupNative
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
"@

    try {
        [void][TeslaStartupNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))
    }
    catch {
        # Windows versions without Per-Monitor V2 still use WPF's normal DPI scaling.
    }

    $consoleHandle = [TeslaStartupNative]::GetConsoleWindow()
    if ($consoleHandle -ne [IntPtr]::Zero) {
        [void][TeslaStartupNative]::ShowWindow($consoleHandle, 0)
    }
}
catch {
    # The animation remains usable if the console cannot be hidden.
}

$scriptRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($script:EntryPath) {
    Split-Path -Parent $script:EntryPath
}
else {
    [Environment]::CurrentDirectory
}

$assetRoot = Join-Path $scriptRoot 'assets'
$assetPaths = [ordered]@{
    CarOff = Join-Path $assetRoot 'car-off.png'
    CarOn  = Join-Path $assetRoot 'car-on.png'
    Fog    = Join-Path $assetRoot 'fog.png'
}

$missingAssets = @($assetPaths.Values | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missingAssets.Count -gt 0) {
    [System.Windows.MessageBox]::Show(
        "The prototype is missing one or more files in the assets folder:`r`n`r`n$($missingAssets -join "`r`n")",
        'Tesla SS Tools - Missing assets',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

function Import-CachedBitmap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
    $bitmap.UriSource = [Uri]::new($Path, [UriKind]::Absolute)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

try {
    # Decode every large image before the window appears to prevent asset pop-in.
    $carOffBitmap = Import-CachedBitmap -Path $assetPaths.CarOff
    $carOnBitmap = Import-CachedBitmap -Path $assetPaths.CarOn
    $fogBitmap = Import-CachedBitmap -Path $assetPaths.Fog

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tesla SS Tools - Startup Animation Prototype"
        WindowStyle="None"
        ResizeMode="NoResize"
        WindowState="Maximized"
        WindowStartupLocation="CenterScreen"
        Background="#050505"
        ShowInTaskbar="False"
        Topmost="True"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        FontFamily="Segoe UI"
        Focusable="True">
    <Window.Resources>
        <Style x:Key="PrototypeButton" TargetType="Button">
            <Setter Property="Foreground" Value="#F2F3F5"/>
            <Setter Property="Background" Value="#171A1F"/>
            <Setter Property="BorderBrush" Value="#343941"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="24,12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonSurface"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Background" Value="#22262D"/>
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#666D78"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Background" Value="#0F1115"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Storyboard x:Key="IntroStoryboard" FillBehavior="HoldEnd">
            <!-- Vehicle reveal -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarOff" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:0" Value="0"/>
                <DiscreteDoubleKeyFrame KeyTime="0:0:0.34" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:0.96" Value="1" KeySpline="0.22,0.61 0.36,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="GroundGlow" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:0.30" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.05" Value="0.42" KeySpline="0.22,0.61 0.36,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarReflection" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:0.38" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.06" Value="0.105" KeySpline="0.22,0.61 0.36,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.82" Value="0.04" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>

            <!-- Secondary title -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="IntroTitle" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:0.72" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.24" Value="0.37" KeySpline="0.22,0.61 0.36,1"/>
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.82" Value="0.37"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.46" Value="0" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="TitleScale"
                             Storyboard.TargetProperty="ScaleX"
                             From="0.982" To="1.015" BeginTime="0:0:0.72" Duration="0:0:1.74"/>
            <DoubleAnimation Storyboard.TargetName="TitleScale"
                             Storyboard.TargetProperty="ScaleY"
                             From="0.982" To="1.015" BeginTime="0:0:0.72" Duration="0:0:1.74"/>

            <!-- Headlight ignition -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarOn" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.17" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.29" Value="1" KeySpline="0.17,0.67 0.28,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="HeadlightBeam" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.16" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.30" Value="0.34" KeySpline="0.1,0.9 0.2,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.62" Value="0.16" KeySpline="0.4,0 0.6,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.58" Value="0.08" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="HeadlightPulse" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.16" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.27" Value="0.50" KeySpline="0.1,0.9 0.2,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.48" Value="0.10" KeySpline="0.4,0 1,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.18" Value="0.04" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>

            <!-- Fog layers -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="FogBack" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.31" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.84" Value="0.20" KeySpline="0.22,0.61 0.36,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.76" Value="0.12" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="FogFront" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.42" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:1.96" Value="0.08" KeySpline="0.22,0.61 0.36,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.78" Value="0.05" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="FogBackTranslate"
                             Storyboard.TargetProperty="X"
                             From="-55" To="35" BeginTime="0:0:1.30" Duration="0:0:1.70"/>
            <DoubleAnimation Storyboard.TargetName="FogFrontTranslate"
                             Storyboard.TargetProperty="X"
                             From="35" To="-30" BeginTime="0:0:1.40" Duration="0:0:1.60"/>

            <!-- Non-linear vehicle launch -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarTranslate" Storyboard.TargetProperty="X">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.76" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.10" Value="58" KeySpline="0.34,0 0.72,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.73" Value="720" KeySpline="0.55,0 0.92,0.72"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="2350" KeySpline="0.60,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarTranslate" Storyboard.TargetProperty="Y">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.76" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.12" Value="5" KeySpline="0.34,0 0.72,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="118" KeySpline="0.60,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarScale" Storyboard.TargetProperty="ScaleX">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.76" Value="1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.12" Value="1.035" KeySpline="0.34,0 0.72,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="2.10" KeySpline="0.60,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarScale" Storyboard.TargetProperty="ScaleY">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.76" Value="1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.12" Value="1.035" KeySpline="0.34,0 0.72,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="2.10" KeySpline="0.60,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarRotate" Storyboard.TargetProperty="Angle">
                <DiscreteDoubleKeyFrame KeyTime="0:0:1.76" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.18" Value="-0.25" KeySpline="0.34,0 0.72,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="-1.15" KeySpline="0.60,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarBlur" Storyboard.TargetProperty="Radius">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.03" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.36" Value="2.4" KeySpline="0.4,0 1,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.90" Value="12" KeySpline="0.4,0 1,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.08" Value="19" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="CarRig" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.72" Value="1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.12" Value="0" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>

            <!-- Passing-car light streak and connected GUI reveal -->
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="TransitionSweep" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.50" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.72" Value="0.58" KeySpline="0.2,0.8 0.3,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.10" Value="0" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="TransitionSweepTranslate"
                             Storyboard.TargetProperty="X"
                             From="-1450" To="2250" BeginTime="0:0:2.47" Duration="0:0:0.62"/>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="TransitionVeil" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.66" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:2.92" Value="0.86" KeySpline="0.2,0.8 0.3,1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.26" Value="0" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="IntroRoot" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.86" Value="1"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.25" Value="0" KeySpline="0.4,0 1,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimationUsingKeyFrames Storyboard.TargetName="GuiRoot" Storyboard.TargetProperty="Opacity">
                <DiscreteDoubleKeyFrame KeyTime="0:0:2.90" Value="0"/>
                <SplineDoubleKeyFrame KeyTime="0:0:3.42" Value="1" KeySpline="0.22,0.61 0.36,1"/>
            </DoubleAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="GuiTranslate"
                             Storyboard.TargetProperty="Y"
                             From="28" To="0" BeginTime="0:0:2.92" Duration="0:0:0.50"/>
            <DoubleAnimation Storyboard.TargetName="GuiScale"
                             Storyboard.TargetProperty="ScaleX"
                             From="0.985" To="1" BeginTime="0:0:2.92" Duration="0:0:0.50"/>
            <DoubleAnimation Storyboard.TargetName="GuiScale"
                             Storyboard.TargetProperty="ScaleY"
                             From="0.985" To="1" BeginTime="0:0:2.92" Duration="0:0:0.50"/>
        </Storyboard>
    </Window.Resources>

    <Grid x:Name="WindowRoot" Background="#050505">
        <!-- The mock GUI is pre-created behind the intro for an instant transition. -->
        <Grid x:Name="GuiRoot" Opacity="0">
            <Grid.Background>
                <RadialGradientBrush Center="0.50,0.43" GradientOrigin="0.50,0.43" RadiusX="0.82" RadiusY="0.88">
                    <GradientStop Color="#171A20" Offset="0"/>
                    <GradientStop Color="#0B0D10" Offset="0.50"/>
                    <GradientStop Color="#050506" Offset="1"/>
                </RadialGradientBrush>
            </Grid.Background>
            <Grid.RenderTransform>
                <TransformGroup>
                    <ScaleTransform x:Name="GuiScale" ScaleX="1" ScaleY="1"/>
                    <TranslateTransform x:Name="GuiTranslate" Y="0"/>
                </TransformGroup>
            </Grid.RenderTransform>

            <Border Width="1060" Height="620"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    CornerRadius="22" Background="#E80D0F12"
                    BorderBrush="#32363D" BorderThickness="1">
                <Border.Effect>
                    <DropShadowEffect Color="#000000" BlurRadius="46" ShadowDepth="14" Opacity="0.72"/>
                </Border.Effect>
                <Grid Margin="54">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Border Width="50" Height="50" CornerRadius="12" Background="#181B20" BorderBrush="#3B4048" BorderThickness="1">
                            <TextBlock Text="T" Foreground="#F2F3F5" FontSize="27" FontWeight="Light" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <StackPanel Grid.Column="1" Margin="18,0,0,0" VerticalAlignment="Center">
                            <TextBlock Text="TESLA SS TOOLS" Foreground="#F5F5F6" FontSize="22" FontWeight="SemiBold"/>
                            <TextBlock Text="ISOLATED STARTUP TEST" Foreground="#747A84" FontSize="10" FontWeight="Bold" Margin="0,4,0,0"/>
                        </StackPanel>
                        <Border Grid.Column="2" CornerRadius="14" Background="#171A1F" BorderBrush="#343941" BorderThickness="1" Padding="13,7">
                            <StackPanel Orientation="Horizontal">
                                <Ellipse Width="7" Height="7" Fill="#D8DADD" Margin="0,0,8,0"/>
                                <TextBlock Text="PROTOTYPE READY" Foreground="#C8CBD0" FontSize="10" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <StackPanel Grid.Row="1" VerticalAlignment="Center" HorizontalAlignment="Center">
                        <TextBlock Text="Tesla SS Tools" Foreground="#F6F6F7" FontSize="58" FontWeight="Light" HorizontalAlignment="Center"/>
                        <Rectangle Height="1" Width="120" Fill="#5E636C" Margin="0,24,0,24"/>
                        <TextBlock Text="Startup Animation Prototype" Foreground="#A8ADB5" FontSize="18" FontWeight="Light" HorizontalAlignment="Center"/>
                        <TextBlock Text="The production Tesla SS Tools application has not been modified."
                                   Foreground="#606670" FontSize="13" HorizontalAlignment="Center" Margin="0,12,0,0"/>
                    </StackPanel>

                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="WPF STORYBOARD  /  LOCAL ASSETS  /  OFFLINE"
                                   Foreground="#555B64" FontSize="10" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                            <Button x:Name="ReplayButton" Content="Replay animation" Style="{StaticResource PrototypeButton}" Margin="0,0,12,0"/>
                            <Button x:Name="CloseButton" Content="Close" Style="{StaticResource PrototypeButton}"/>
                        </StackPanel>
                    </Grid>
                </Grid>
            </Border>
        </Grid>

        <Viewbox x:Name="IntroRoot" Stretch="UniformToFill" StretchDirection="Both" Opacity="1">
            <Grid Width="1920" Height="1080" ClipToBounds="True">
                <Grid.Background>
                    <RadialGradientBrush Center="0.51,0.57" GradientOrigin="0.51,0.57" RadiusX="0.78" RadiusY="0.78">
                        <GradientStop Color="#17191C" Offset="0"/>
                        <GradientStop Color="#090A0C" Offset="0.48"/>
                        <GradientStop Color="#050505" Offset="1"/>
                    </RadialGradientBrush>
                </Grid.Background>

                <Rectangle IsHitTestVisible="False">
                    <Rectangle.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="#000000" Offset="0"/>
                            <GradientStop Color="#00000000" Offset="0.30"/>
                            <GradientStop Color="#15000000" Offset="0.68"/>
                            <GradientStop Color="#B8000000" Offset="1"/>
                        </LinearGradientBrush>
                    </Rectangle.Fill>
                </Rectangle>

                <Ellipse x:Name="GroundGlow" Width="1390" Height="215" Opacity="0"
                         HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,88">
                    <Ellipse.Fill>
                        <RadialGradientBrush>
                            <GradientStop Color="#48515966" Offset="0"/>
                            <GradientStop Color="#17252A30" Offset="0.48"/>
                            <GradientStop Color="#00000000" Offset="1"/>
                        </RadialGradientBrush>
                    </Ellipse.Fill>
                    <Ellipse.Effect>
                        <BlurEffect Radius="24"/>
                    </Ellipse.Effect>
                </Ellipse>

                <Rectangle Height="2" Width="1500" VerticalAlignment="Bottom" Margin="0,0,0,157" Opacity="0.28">
                    <Rectangle.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#00000000" Offset="0"/>
                            <GradientStop Color="#40565B61" Offset="0.36"/>
                            <GradientStop Color="#66747A82" Offset="0.52"/>
                            <GradientStop Color="#00000000" Offset="1"/>
                        </LinearGradientBrush>
                    </Rectangle.Fill>
                </Rectangle>

                <TextBlock x:Name="IntroTitle" Text="TESLA SS TOOLS" Opacity="0"
                           Foreground="#F3F3F4" FontSize="70" FontWeight="Light"
                           HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,214,0,0"
                           RenderTransformOrigin="0.5,0.5">
                    <TextBlock.RenderTransform>
                        <ScaleTransform x:Name="TitleScale" ScaleX="1" ScaleY="1"/>
                    </TextBlock.RenderTransform>
                    <TextBlock.Effect>
                        <DropShadowEffect Color="#FFFFFF" BlurRadius="18" ShadowDepth="0" Opacity="0.12"/>
                    </TextBlock.Effect>
                </TextBlock>

                <Image x:Name="FogBack" Width="2240" Height="746" Opacity="0"
                       HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,-85"
                       Stretch="Uniform" RenderOptions.BitmapScalingMode="Fant">
                    <Image.RenderTransform>
                        <TranslateTransform x:Name="FogBackTranslate" X="-55"/>
                    </Image.RenderTransform>
                </Image>

                <Canvas x:Name="CarRig" Width="1920" Height="1080" RenderTransformOrigin="0.66,0.64">
                    <Canvas.RenderTransform>
                        <TransformGroup>
                            <ScaleTransform x:Name="CarScale" ScaleX="1" ScaleY="1"/>
                            <RotateTransform x:Name="CarRotate" Angle="0"/>
                            <TranslateTransform x:Name="CarTranslate" X="0" Y="0"/>
                        </TransformGroup>
                    </Canvas.RenderTransform>
                    <Canvas.Effect>
                        <BlurEffect x:Name="CarBlur" Radius="0" RenderingBias="Performance"/>
                    </Canvas.Effect>

                    <Path x:Name="HeadlightBeam" Opacity="0" Data="M 1305,587 L 1940,480 L 1940,730 L 1305,650 Z">
                        <Path.Fill>
                            <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
                                <GradientStop Color="#70F7F9FA" Offset="0"/>
                                <GradientStop Color="#24E8EBEF" Offset="0.38"/>
                                <GradientStop Color="#00E3E7EC" Offset="1"/>
                            </LinearGradientBrush>
                        </Path.Fill>
                        <Path.Effect>
                            <BlurEffect Radius="22"/>
                        </Path.Effect>
                    </Path>

                    <Image x:Name="CarReflection" Canvas.Left="275" Canvas.Top="978"
                           Width="1270" Height="635" Opacity="0" Stretch="Uniform"
                           RenderTransformOrigin="0.5,0">
                        <Image.RenderTransform>
                            <ScaleTransform ScaleX="1" ScaleY="-0.31"/>
                        </Image.RenderTransform>
                        <Image.OpacityMask>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                <GradientStop Color="#9EFFFFFF" Offset="0"/>
                                <GradientStop Color="#24FFFFFF" Offset="0.52"/>
                                <GradientStop Color="#00FFFFFF" Offset="1"/>
                            </LinearGradientBrush>
                        </Image.OpacityMask>
                        <Image.Effect>
                            <BlurEffect Radius="8"/>
                        </Image.Effect>
                    </Image>

                    <Image x:Name="CarOff" Canvas.Left="275" Canvas.Top="342"
                           Width="1270" Height="635" Opacity="0" Stretch="Uniform"
                           RenderOptions.BitmapScalingMode="HighQuality"/>
                    <Image x:Name="CarOn" Canvas.Left="275" Canvas.Top="342"
                           Width="1270" Height="635" Opacity="0" Stretch="Uniform"
                           RenderOptions.BitmapScalingMode="HighQuality"/>

                    <Path x:Name="HeadlightPulse" Opacity="0" Data="M 1290,565 L 1630,528 L 1715,675 L 1300,658 Z">
                        <Path.Fill>
                            <RadialGradientBrush Center="0.12,0.48" GradientOrigin="0.12,0.48" RadiusX="0.92" RadiusY="0.68">
                                <GradientStop Color="#C8FFFFFF" Offset="0"/>
                                <GradientStop Color="#34FFFFFF" Offset="0.28"/>
                                <GradientStop Color="#00FFFFFF" Offset="1"/>
                            </RadialGradientBrush>
                        </Path.Fill>
                        <Path.Effect>
                            <BlurEffect Radius="30"/>
                        </Path.Effect>
                    </Path>
                </Canvas>

                <Image x:Name="FogFront" Width="2370" Height="790" Opacity="0"
                       HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,-220"
                       Stretch="Uniform" RenderOptions.BitmapScalingMode="Fant">
                    <Image.RenderTransform>
                        <TranslateTransform x:Name="FogFrontTranslate" X="35"/>
                    </Image.RenderTransform>
                    <Image.Effect>
                        <BlurEffect Radius="2.4" RenderingBias="Performance"/>
                    </Image.Effect>
                </Image>

                <Border x:Name="TransitionSweep" Width="850" Height="1450" Opacity="0"
                        HorizontalAlignment="Left" VerticalAlignment="Center"
                        RenderTransformOrigin="0.5,0.5">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0.5" EndPoint="1,0.5">
                            <GradientStop Color="#00FFFFFF" Offset="0"/>
                            <GradientStop Color="#30FFFFFF" Offset="0.36"/>
                            <GradientStop Color="#B0FFFFFF" Offset="0.53"/>
                            <GradientStop Color="#20FFFFFF" Offset="0.68"/>
                            <GradientStop Color="#00FFFFFF" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <Border.RenderTransform>
                        <TransformGroup>
                            <SkewTransform AngleX="-18"/>
                            <TranslateTransform x:Name="TransitionSweepTranslate" X="-1450"/>
                        </TransformGroup>
                    </Border.RenderTransform>
                    <Border.Effect>
                        <BlurEffect Radius="34" RenderingBias="Performance"/>
                    </Border.Effect>
                </Border>

                <Rectangle x:Name="TransitionVeil" Fill="#050505" Opacity="0"/>

                <Border Width="1760" Height="920" BorderBrush="#11FFFFFF" BorderThickness="1" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False"/>
            </Grid>
        </Viewbox>
    </Grid>
</Window>
"@

    $xmlReader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)

    $script:Window = $window
    $script:IntroRoot = $window.FindName('IntroRoot')
    $script:GuiRoot = $window.FindName('GuiRoot')
    $script:CarOff = $window.FindName('CarOff')
    $script:CarOn = $window.FindName('CarOn')
    $script:CarReflection = $window.FindName('CarReflection')
    $script:FogBack = $window.FindName('FogBack')
    $script:FogFront = $window.FindName('FogFront')
    $script:ReplayButton = $window.FindName('ReplayButton')
    $script:CloseButton = $window.FindName('CloseButton')
    $script:Storyboard = $window.Resources['IntroStoryboard']
    $script:IntroRunning = $false

    $script:CarOff.Source = $carOffBitmap
    $script:CarOn.Source = $carOnBitmap
    $script:CarReflection.Source = $carOffBitmap
    $script:FogBack.Source = $fogBitmap
    $script:FogFront.Source = $fogBitmap

    function Start-TeslaIntro {
        if ($script:IntroRunning) {
            return
        }

        try {
            $script:Storyboard.Remove($script:Window)
        }
        catch {
            # There is no active clock on the first run.
        }

        $script:IntroRoot.Visibility = [System.Windows.Visibility]::Visible
        $script:IntroRoot.Opacity = 1
        $script:GuiRoot.Opacity = 0
        $script:Window.Topmost = $true
        $script:Window.ShowInTaskbar = $false
        $script:Window.Cursor = [System.Windows.Input.Cursors]::None
        $script:IntroRunning = $true
        $script:Storyboard.Begin($script:Window, $true)
    }

    function Complete-TeslaIntro {
        $script:IntroRunning = $false
        $script:IntroRoot.Visibility = [System.Windows.Visibility]::Collapsed
        $script:Window.Topmost = $false
        $script:Window.ShowInTaskbar = $true
        $script:Window.Cursor = [System.Windows.Input.Cursors]::Arrow
        $script:ReplayButton.Focus() | Out-Null
    }

    $script:Storyboard.Add_Completed({ Complete-TeslaIntro })

    $script:ReplayButton.Add_Click({ Start-TeslaIntro })
    $script:CloseButton.Add_Click({ $script:Window.Close() })

    $window.Add_KeyDown({
        param($sender, $eventArgs)

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($script:IntroRunning) {
                $script:Storyboard.SkipToFill($script:Window)
                Complete-TeslaIntro
            }
            else {
                $script:Window.Close()
            }
            $eventArgs.Handled = $true
        }
    })

    $window.Add_Loaded({
        $script:Window.Activate() | Out-Null
        $script:Window.Focus() | Out-Null
        Start-TeslaIntro
    })

    $window.ShowDialog() | Out-Null
}
catch {
    try {
        [System.Windows.MessageBox]::Show(
            "The startup prototype could not be opened.`r`n`r`n$($_.Exception.Message)",
            'Tesla SS Tools - Prototype error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        Write-Error $_.Exception.Message
    }
    exit 1
}
