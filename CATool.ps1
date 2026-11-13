<#
  C/A Tool - on-screen overlay for measuring the condylar (C) and axial (A) circles
  on an X-ray or CBCT image shown in any viewer (used in EPIC and Advanced Orthogonal).

  How the measurement works
  - Each set (C and A) has 4 points, placed in any order.
  - The two outside points (the two ends of the arc) are shared by both circles.
    Inner point 1 + the outside points make circle 1; inner point 2 + the outside
    points make circle 2. The set's result is the average of the two diameters.
  - The distance between the two C outside points is taken as a known length
    (55 mm by default, adjustable) to convert screen distance into millimeters.
  - Ratio = C average diameter / A average diameter (no units).

  Runs on the Windows PowerShell 5.1 and WPF built into Windows. Nothing to install.
  Settings are kept in %APPDATA%\CATool\settings.json; errors go to error.log there.
  Start it with "Start CA Tool.cmd".

  Keep this file plain ASCII: Windows PowerShell 5.1 misreads non-ASCII in files
  saved without a byte-order mark.
#>

$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'

$script:DataDir      = Join-Path $env:APPDATA 'CATool'
$script:SettingsPath = Join-Path $script:DataDir 'settings.json'
$script:LogPath      = Join-Path $script:DataDir 'error.log'

function Write-ErrorLog([string]$Message) {
    try {
        if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir | Out-Null }
        Add-Content -Path $script:LogPath -Value ('{0}  {1}' -f (Get-Date -Format s), $Message)
    } catch { }
}

# ---------------------------------------------------------------------------
# Geometry (pure functions; no UI)
# ---------------------------------------------------------------------------

function Get-Distance($P, $Q) {
    $dx = [double]$P.X - [double]$Q.X
    $dy = [double]$P.Y - [double]$Q.Y
    [math]::Sqrt($dx * $dx + $dy * $dy)
}

# Circle through three points. Returns $null when the points are (nearly) in a line.
function Get-CircleFrom3($P1, $P2, $P3) {
    $ax = [double]$P1.X; $ay = [double]$P1.Y
    $bx = [double]$P2.X; $by = [double]$P2.Y
    $cx = [double]$P3.X; $cy = [double]$P3.Y
    $d = 2.0 * ($ax * ($by - $cy) + $bx * ($cy - $ay) + $cx * ($ay - $by))
    $span = [math]::Max((Get-Distance $P1 $P2), [math]::Max((Get-Distance $P2 $P3), (Get-Distance $P1 $P3)))
    if ($span -le 0 -or [math]::Abs($d) -lt 1e-6 * $span * $span) { return $null }
    $a2 = $ax * $ax + $ay * $ay
    $b2 = $bx * $bx + $by * $by
    $c2 = $cx * $cx + $cy * $cy
    $ux = ($a2 * ($by - $cy) + $b2 * ($cy - $ay) + $c2 * ($ay - $by)) / $d
    $uy = ($a2 * ($cx - $bx) + $b2 * ($ax - $cx) + $c2 * ($bx - $ax)) / $d
    $center = [pscustomobject]@{ X = $ux; Y = $uy }
    [pscustomobject]@{ X = $ux; Y = $uy; R = (Get-Distance $center $P1) }
}

# Least-squares circle through any number of points (algebraic fit). Used only to
# find the order of the points around the arc. Returns $null for a straight line.
function Get-FitCircle($Pts) {
    $n = $Pts.Count
    $mx = 0.0; $my = 0.0
    foreach ($p in $Pts) { $mx += $p.X; $my += $p.Y }
    $mx /= $n; $my /= $n
    $sxx = 0.0; $syy = 0.0; $sxy = 0.0; $sxz = 0.0; $syz = 0.0
    foreach ($p in $Pts) {
        $x = $p.X - $mx; $y = $p.Y - $my; $z = $x * $x + $y * $y
        $sxx += $x * $x; $syy += $y * $y; $sxy += $x * $y
        $sxz += $x * $z; $syz += $y * $z
    }
    $det = $sxx * $syy - $sxy * $sxy
    $scale = $sxx + $syy
    if ($scale -le 0 -or [math]::Abs($det) -lt 1e-9 * $scale * $scale) { return $null }
    $dCoef = (-$sxz * $syy + $syz * $sxy) / $det
    $eCoef = (-$syz * $sxx + $sxz * $sxy) / $det
    [pscustomobject]@{ X = $mx - $dCoef / 2.0; Y = $my - $eCoef / 2.0 }
}

# Which two of the four points are the outside points (the ends of the arc)?
# The points are ordered by angle around a best-fit center; the two points on either
# side of the biggest empty gap are the arc's ends. Falls back to the farthest-apart
# pair if no circle can be fitted. Returns indexes into $Pts.
function Get-OuterInner($Pts) {
    $outer = $null
    $fit = Get-FitCircle $Pts
    if ($fit) {
        $order = @(0..3 | Sort-Object { [math]::Atan2($Pts[$_].Y - $fit.Y, $Pts[$_].X - $fit.X) })
        $bestGap = -1.0; $bestI = 0
        for ($i = 0; $i -lt 4; $i++) {
            $a1 = [math]::Atan2($Pts[$order[$i]].Y - $fit.Y, $Pts[$order[$i]].X - $fit.X)
            $a2 = [math]::Atan2($Pts[$order[($i + 1) % 4]].Y - $fit.Y, $Pts[$order[($i + 1) % 4]].X - $fit.X)
            $gap = $a2 - $a1
            if ($gap -le 0) { $gap += 2 * [math]::PI }
            if ($gap -gt $bestGap) { $bestGap = $gap; $bestI = $i }
        }
        $outer = @($order[$bestI], $order[($bestI + 1) % 4])
    } else {
        $best = -1.0
        for ($i = 0; $i -lt 4; $i++) {
            for ($j = $i + 1; $j -lt 4; $j++) {
                $d = Get-Distance $Pts[$i] $Pts[$j]
                if ($d -gt $best) { $best = $d; $outer = @($i, $j) }
            }
        }
    }
    $inner = @(0..3 | Where-Object { $outer -notcontains $_ })
    [pscustomobject]@{ Outer = $outer; Inner = $inner }
}

# Full result for one set of four points (or $null if the set is not complete).
# AvgDiam is in screen units: ((2*R1) + (2*R2)) / 2 = R1 + R2.
function Get-SetResult($Pts) {
    $Pts = @($Pts)
    if ($Pts.Count -lt 4) { return $null }
    $oi = Get-OuterInner $Pts
    $o1 = $Pts[$oi.Outer[0]]; $o2 = $Pts[$oi.Outer[1]]
    $i1 = $Pts[$oi.Inner[0]]; $i2 = $Pts[$oi.Inner[1]]
    $c1 = Get-CircleFrom3 $o1 $o2 $i1
    $c2 = Get-CircleFrom3 $o1 $o2 $i2
    $avg = $null
    if ($c1 -and $c2) { $avg = $c1.R + $c2.R }
    $avgCircle = $null
    if ($c1 -and $c2) { $avgCircle = Get-AverageCircle $o1 $o2 $c1 $c2 }
    [pscustomobject]@{
        Outer = @($o1, $o2); Inner = @($i1, $i2)
        C1 = $c1; C2 = $c2
        OuterDist = (Get-Distance $o1 $o2)
        AvgDiam = $avg
        AvgCircle = $avgCircle
    }
}

# The averaged circle, for drawing: radius = average of the two radii, passing through
# both outside points. Both circle centers lie on the perpendicular bisector of the
# outside points; the averaged center sits on that same line, on the side where the
# two centers lie on average.
function Get-AverageCircle($O1, $O2, $C1, $C2) {
    $r = ($C1.R + $C2.R) / 2.0
    $mx = ($O1.X + $O2.X) / 2.0; $my = ($O1.Y + $O2.Y) / 2.0
    $chord = Get-Distance $O1 $O2
    if ($chord -le 0) { return $null }
    $nx = -($O2.Y - $O1.Y) / $chord; $ny = ($O2.X - $O1.X) / $chord   # unit normal to the chord
    $off1 = ($C1.X - $mx) * $nx + ($C1.Y - $my) * $ny
    $off2 = ($C2.X - $mx) * $nx + ($C2.Y - $my) * $ny
    $h = $chord / 2.0
    $dist = [math]::Sqrt([math]::Max(0.0, $r * $r - $h * $h))
    if (($off1 + $off2) -lt 0) { $dist = -$dist }
    [pscustomobject]@{ X = $mx + $dist * $nx; Y = $my + $dist * $ny; R = $r }
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

$script:Settings = [ordered]@{
    ColorC      = '#00E5FF'
    ColorA      = '#FF9800'
    PointSize   = 14
    OuterMm     = 55.0      # always stored in mm; shown in the chosen unit
    Units       = 'in'      # 'in' or 'mm'
    ShowCircles = $true
    HotkeyKey   = 'F8'      # WPF key name; '' = no hotkey
    HotkeyMods  = 0         # 1 Alt, 2 Ctrl, 4 Shift, 8 Win (same values as Windows uses)
    ToolLeft    = $null
    ToolTop     = $null
}

function Read-Settings {
    if (-not (Test-Path $script:SettingsPath)) { return }
    try {
        $j = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
        foreach ($k in @($script:Settings.Keys)) {
            if ($null -ne $j.$k) { $script:Settings[$k] = $j.$k }
        }
    } catch { Write-ErrorLog "Could not read settings: $_" }
}

function Save-Settings {
    try {
        if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir | Out-Null }
        $script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    } catch { Write-ErrorLog "Could not save settings: $_" }
}

# ---------------------------------------------------------------------------
# User interface
# ---------------------------------------------------------------------------

function Start-CATool {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    if (-not ('CATool.Native' -as [type])) {
        Add-Type -Namespace CATool -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
'@
    }
    # System-wide hotkey: works even while the image viewer has the keyboard.
    if (-not ('CATool.Hotkey' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace CATool {
    public class Hotkey : NativeWindow, IDisposable {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        public event EventHandler Pressed;
        bool registered;
        public Hotkey() { CreateHandle(new CreateParams()); }
        public bool Set(uint mods, uint vk) {
            Clear();
            registered = RegisterHotKey(Handle, 1, mods | 0x4000, vk);   // 0x4000 = no auto-repeat
            return registered;
        }
        public void Clear() { if (registered) { UnregisterHotKey(Handle, 1); registered = false; } }
        protected override void WndProc(ref Message m) {
            if (m.Msg == 0x0312 && Pressed != null) { Pressed(this, EventArgs.Empty); }
            base.WndProc(ref m);
        }
        public void Dispose() { Clear(); DestroyHandle(); }
    }
}
'@
    }

    Read-Settings

    $script:Points  = New-Object System.Collections.ArrayList
    $script:Seq     = 0
    $script:Active  = 'C'
    $script:Paused  = $false
    $script:Drag    = $null
    $script:Hover   = $null
    $script:Loading = $false   # true while the code itself fills a text box
    $script:Palette = @('#00E5FF', '#FFEB3B', '#FF9800', '#FF1744', '#FF40FF', '#76FF03', '#2979FF', '#FFFFFF')

    # --- Overlay: a see-through window over every monitor -----------------------
    $script:Overlay = New-Object System.Windows.Window
    $ov = $script:Overlay
    $ov.WindowStyle        = 'None'
    $ov.AllowsTransparency = $true
    $ov.Background         = [System.Windows.Media.Brushes]::Transparent
    $ov.Topmost            = $true
    $ov.ShowInTaskbar      = $false
    $ov.ResizeMode         = 'NoResize'
    $ov.WindowStartupLocation = 'Manual'
    $ov.Left   = [System.Windows.SystemParameters]::VirtualScreenLeft
    $ov.Top    = [System.Windows.SystemParameters]::VirtualScreenTop
    $ov.Width  = [System.Windows.SystemParameters]::VirtualScreenWidth
    $ov.Height = [System.Windows.SystemParameters]::VirtualScreenHeight
    $ov.Cursor = [System.Windows.Input.Cursors]::Cross

    # Alpha 1/255: invisible to the eye, but still catches mouse clicks.
    $script:CatchBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(1, 0, 0, 0))
    $script:Canvas = New-Object System.Windows.Controls.Canvas
    $script:Canvas.Background = $script:CatchBrush
    $ov.Content = $script:Canvas

    # --- Toolbox --------------------------------------------------------------------
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="C/A Tool v{VERSION}" WindowStyle="ToolWindow" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" Topmost="True" ShowInTaskbar="True"
        WindowStartupLocation="Manual" FontFamily="Segoe UI" FontSize="13"
        Background="#FFF5F5F5">
  <StackPanel Margin="10" Width="240">
    <TextBlock Text="Placing points for" FontSize="11" Foreground="#FF555555"/>
    <Grid Margin="0,4,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition/><ColumnDefinition Width="6"/><ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <ToggleButton x:Name="BtnC" Grid.Column="0" Padding="6,5" ToolTip="Place condylar points">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="SwC" Width="12" Height="12" Stroke="Black" StrokeThickness="1" Margin="0,0,6,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="TxtC" Text="C  0/4" FontWeight="Bold"/>
        </StackPanel>
      </ToggleButton>
      <ToggleButton x:Name="BtnA" Grid.Column="2" Padding="6,5" ToolTip="Place axial points">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="SwA" Width="12" Height="12" Stroke="Black" StrokeThickness="1" Margin="0,0,6,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="TxtA" Text="A  0/4" FontWeight="Bold"/>
        </StackPanel>
      </ToggleButton>
    </Grid>
    <TextBlock x:Name="Hint" Margin="0,6,0,0" TextWrapping="Wrap" FontSize="11" Foreground="#FF555555"/>
    <Border Margin="0,8,0,0" Padding="8" Background="White" BorderBrush="#FFCCCCCC" BorderThickness="1" CornerRadius="4">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="C average diameter"/>
        <TextBlock Grid.Row="0" Grid.Column="1" x:Name="ValC" FontWeight="Bold" Text="&#x2014;"/>
        <TextBlock Grid.Row="1" Text="A average diameter" Margin="0,4,0,0"/>
        <TextBlock Grid.Row="1" Grid.Column="1" x:Name="ValA" FontWeight="Bold" Text="&#x2014;" Margin="0,4,0,0"/>
        <TextBlock Grid.Row="2" Text="Ratio  C &#x00F7; A" Margin="0,4,0,0"/>
        <TextBlock Grid.Row="2" Grid.Column="1" x:Name="ValR" FontWeight="Bold" Text="&#x2014;" Margin="0,4,0,0"/>
      </Grid>
    </Border>
    <UniformGrid Columns="3" Margin="0,8,0,0">
      <Button x:Name="BtnUndo" Content="Undo" Margin="0,0,3,0" Padding="2,3" ToolTip="Remove the last point placed (Ctrl+Z)"/>
      <Button x:Name="BtnClearC" Content="Clear C" Margin="3,0,3,0" Padding="2,3"/>
      <Button x:Name="BtnClearA" Content="Clear A" Margin="3,0,0,0" Padding="2,3"/>
    </UniformGrid>
    <Button x:Name="BtnClearAll" Content="Clear all" Margin="0,6,0,0" Padding="2,3"/>
    <ToggleButton x:Name="BtnPause" Content="Pause (use the viewer)" Margin="0,6,0,0" Padding="2,4"
                  ToolTip="While paused, clicks go through to the image viewer underneath"/>
    <Expander Header="Preferences" Margin="0,8,0,0">
      <StackPanel Margin="0,6,0,0">
        <Grid>
          <TextBlock Text="Point size"/>
          <TextBlock x:Name="TxtSize" HorizontalAlignment="Right" Text="14"/>
        </Grid>
        <Slider x:Name="SldSize" Minimum="4" Maximum="40" SmallChange="1" LargeChange="4" IsSnapToTickEnabled="True" TickFrequency="1"/>
        <TextBlock Text="C color" Margin="0,8,0,2"/>
        <WrapPanel x:Name="PalC"/>
        <TextBlock Text="A color" Margin="0,8,0,2"/>
        <WrapPanel x:Name="PalA"/>
        <TextBlock Text="Units" Margin="0,8,0,2"/>
        <StackPanel Orientation="Horizontal">
          <RadioButton x:Name="RadIn" Content="Inches" GroupName="Units" Margin="0,0,14,0"/>
          <RadioButton x:Name="RadMm" Content="Millimeters" GroupName="Units"/>
        </StackPanel>
        <TextBlock x:Name="LblRef" Text="Distance between C outside points" Margin="0,8,0,2" TextWrapping="Wrap"/>
        <TextBox x:Name="TxtMm" Width="80" HorizontalAlignment="Left" Padding="2"/>
        <CheckBox x:Name="ChkCircles" Content="Show averaged circles" Margin="0,8,0,0"/>
        <TextBlock Text="Pause hotkey (click the box, then press a key; Delete = none)" Margin="0,8,0,2" TextWrapping="Wrap"/>
        <TextBox x:Name="TxtHotkey" Width="140" HorizontalAlignment="Left" Padding="2" IsReadOnly="True" IsReadOnlyCaretVisible="False"/>
        <TextBlock x:Name="HotkeyMsg" FontSize="11" Foreground="#FFB00020" TextWrapping="Wrap"/>
      </StackPanel>
    </Expander>
    <Button x:Name="BtnExit" Content="Exit" Margin="0,10,0,0" Padding="2,4"/>
  </StackPanel>
</Window>
'@
    $script:Toolbox = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $script:Toolbox.Title = $script:Toolbox.Title.Replace('{VERSION}', $script:Version)
    $script:Ui = @{}
    foreach ($name in 'BtnC', 'BtnA', 'SwC', 'SwA', 'TxtC', 'TxtA', 'Hint', 'ValC', 'ValA', 'ValR',
                      'BtnUndo', 'BtnClearC', 'BtnClearA', 'BtnClearAll', 'BtnPause',
                      'TxtSize', 'SldSize', 'PalC', 'PalA', 'TxtMm', 'ChkCircles', 'BtnExit',
                      'RadIn', 'RadMm', 'LblRef', 'TxtHotkey', 'HotkeyMsg') {
        $script:Ui[$name] = $script:Toolbox.FindName($name)
    }
    $ui = $script:Ui

    # Toolbox position: last saved spot if still on screen, else top-right of the main screen.
    $vl = [System.Windows.SystemParameters]::VirtualScreenLeft
    $vt = [System.Windows.SystemParameters]::VirtualScreenTop
    $vr = $vl + [System.Windows.SystemParameters]::VirtualScreenWidth
    $vb = $vt + [System.Windows.SystemParameters]::VirtualScreenHeight
    $tl = $script:Settings.ToolLeft; $tt = $script:Settings.ToolTop
    if ($null -ne $tl -and $null -ne $tt -and $tl -ge $vl -and $tl -le ($vr - 100) -and $tt -ge $vt -and $tt -le ($vb - 100)) {
        $script:Toolbox.Left = [double]$tl; $script:Toolbox.Top = [double]$tt
    } else {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $script:Toolbox.Left = $wa.Right - 290
        $script:Toolbox.Top  = $wa.Top + 40
    }

    # Color swatches
    foreach ($set in 'C', 'A') {
        foreach ($hex in $script:Palette) {
            $b = New-Object System.Windows.Controls.Button
            $b.Width = 22; $b.Height = 22
            $b.Margin = New-Object System.Windows.Thickness 2
            $b.Background = New-Brush $hex
            $b.Tag = "$set|$hex"
            $b.ToolTip = $hex
            $b.Add_Click({
                param($s, $e)
                $parts = ([string]$s.Tag).Split('|')
                $script:Settings['Color' + $parts[0]] = $parts[1]
                Update-View
            })
            [void]$ui['Pal' + $set].Children.Add($b)
        }
    }

    # Preference controls: load current values
    $ui.SldSize.Value = [double]$script:Settings.PointSize
    $ui.TxtSize.Text = [string][int]$script:Settings.PointSize
    if ($script:Settings.Units -ne 'mm') { $script:Settings.Units = 'in' }
    $ui.RadIn.IsChecked = ($script:Settings.Units -eq 'in')
    $ui.RadMm.IsChecked = ($script:Settings.Units -eq 'mm')
    Show-ReferenceLength
    $ui.ChkCircles.IsChecked = [bool]$script:Settings.ShowCircles

    # --- Events ---------------------------------------------------------------------
    $script:Canvas.Add_MouseLeftButtonDown({
        param($s, $e)
        $pos = $e.GetPosition($script:Canvas)
        $hit = Find-NearestPoint $pos
        if ($hit) {
            $script:Drag = $hit
            [void]$script:Canvas.CaptureMouse()
        } else {
            Add-Point $pos
        }
        $e.Handled = $true
    })
    $script:Canvas.Add_MouseMove({
        param($s, $e)
        $pos = $e.GetPosition($script:Canvas)
        if ($null -ne $script:Drag) {
            $script:Drag.X = $pos.X; $script:Drag.Y = $pos.Y
            Update-View
        } else {
            Set-Hover (Find-NearestPoint $pos)
        }
    })
    $script:Canvas.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($null -ne $script:Drag) {
            $script:Drag = $null
            $script:Canvas.ReleaseMouseCapture()
            Set-Hover (Find-NearestPoint ($e.GetPosition($script:Canvas)))
        }
    })
    $script:Canvas.Add_MouseLeave({ if ($null -eq $script:Drag) { Set-Hover $null } })
    $script:Canvas.Add_MouseRightButtonDown({
        param($s, $e)
        $hit = Find-NearestPoint ($e.GetPosition($script:Canvas))
        if ($hit) {
            $script:Points.Remove($hit)
            $script:Active = $hit.Set
            $script:Hover = $null
            Update-View
        }
        $e.Handled = $true
    })

    $keyHandler = {
        param($s, $e)
        if ($e.Key -eq 'Z' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            Undo-Point
            $e.Handled = $true
        }
    }
    $script:Overlay.Add_KeyDown($keyHandler)
    $script:Toolbox.Add_KeyDown($keyHandler)

    $ui.BtnC.Add_Click({ $script:Active = 'C'; Update-View })
    $ui.BtnA.Add_Click({ $script:Active = 'A'; Update-View })
    $ui.BtnUndo.Add_Click({ Undo-Point })
    $ui.BtnClearC.Add_Click({ Clear-Set 'C' })
    $ui.BtnClearA.Add_Click({ Clear-Set 'A' })
    $ui.BtnClearAll.Add_Click({ $script:Points.Clear(); $script:Active = 'C'; Update-View })
    $ui.BtnPause.Add_Click({ Set-Paused ([bool]$script:Ui.BtnPause.IsChecked) })
    $ui.SldSize.Add_ValueChanged({
        param($s, $e)
        $script:Settings.PointSize = [int][math]::Round($s.Value)
        $script:Ui.TxtSize.Text = [string]$script:Settings.PointSize
        Update-View
    })
    $ui.TxtMm.Add_TextChanged({
        param($s, $e)
        if ($script:Loading) { return }
        $v = 0.0
        if ([double]::TryParse($s.Text, [ref]$v) -and $v -gt 0) {
            if ($script:Settings.Units -eq 'in') { $v = $v * 25.4 }
            $script:Settings.OuterMm = $v
            $s.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        } else {
            $s.Background = New-Brush '#FFFFD6D6'
        }
        Update-View
    })
    $ui.RadIn.Add_Click({ $script:Settings.Units = 'in'; Show-ReferenceLength; Update-View })
    $ui.RadMm.Add_Click({ $script:Settings.Units = 'mm'; Show-ReferenceLength; Update-View })
    $ui.ChkCircles.Add_Click({ $script:Settings.ShowCircles = [bool]$script:Ui.ChkCircles.IsChecked; Update-View })
    $ui.BtnExit.Add_Click({ $script:Toolbox.Close() })

    # Pause hotkey: toggles pause from anywhere. While the hotkey box has focus the
    # hotkey is switched off, so the current key can be pressed to re-pick it.
    $script:Hotkey = New-Object CATool.Hotkey
    $script:Hotkey.add_Pressed({ Set-Paused (-not $script:Paused) })
    $ui.TxtHotkey.Add_GotKeyboardFocus({ $script:Hotkey.Clear(); $script:Ui.HotkeyMsg.Text = 'Press the key you want...' })
    $ui.TxtHotkey.Add_LostKeyboardFocus({ Register-PauseHotkey })
    $ui.TxtHotkey.Add_PreviewKeyDown({
        param($s, $e)
        $key = $e.Key
        if ($key -eq 'System') { $key = $e.SystemKey }
        if ($key -eq 'Tab') { return }
        $e.Handled = $true
        if (@('LeftCtrl', 'RightCtrl', 'LeftShift', 'RightShift', 'LeftAlt', 'RightAlt', 'LWin', 'RWin') -contains [string]$key) { return }
        if ($key -eq 'Delete' -or $key -eq 'Back' -or $key -eq 'Escape') {
            $script:Settings.HotkeyKey = ''; $script:Settings.HotkeyMods = 0
        } else {
            $script:Settings.HotkeyKey = [string]$key
            $script:Settings.HotkeyMods = [int][System.Windows.Input.Keyboard]::Modifiers
        }
        $script:Ui.TxtHotkey.Text = Format-Hotkey
        $script:Ui.HotkeyMsg.Text = 'Click anywhere else to save it.'
    })

    $script:Toolbox.Add_Closing({
        $script:Settings.ToolLeft = $script:Toolbox.Left
        $script:Settings.ToolTop  = $script:Toolbox.Top
    })
    $script:Toolbox.Add_Closed({
        Save-Settings
        try { $script:Hotkey.Dispose() } catch { }
        try { $script:Overlay.Close() } catch { }
        $script:App.Shutdown()
    })

    # --- Run ------------------------------------------------------------------------
    $script:App = New-Object System.Windows.Application
    $script:App.ShutdownMode = 'OnExplicitShutdown'
    $script:App.Add_DispatcherUnhandledException({
        param($s, $e)
        Write-ErrorLog $e.Exception.ToString()
        $e.Handled = $true
    })

    $script:Overlay.Show()
    $script:Toolbox.Owner = $script:Overlay   # owned window always sits above the overlay
    $script:Toolbox.Show()
    Register-PauseHotkey
    Update-View
    [void]$script:App.Run()
}

function Format-Hotkey {
    $key = [string]$script:Settings.HotkeyKey
    if (-not $key) { return '(none)' }
    $mods = [int]$script:Settings.HotkeyMods
    $parts = @()
    if ($mods -band 2) { $parts += 'Ctrl' }
    if ($mods -band 1) { $parts += 'Alt' }
    if ($mods -band 4) { $parts += 'Shift' }
    if ($mods -band 8) { $parts += 'Win' }
    ($parts + $key) -join '+'
}

# Register the saved pause hotkey and show the result in the toolbox.
function Register-PauseHotkey {
    $ui = $script:Ui
    $ui.TxtHotkey.Text = Format-Hotkey
    $ui.HotkeyMsg.Text = ''
    $script:Hotkey.Clear()
    $key = [string]$script:Settings.HotkeyKey
    if ($key) {
        $ok = $false
        try {
            $wpfKey = [System.Windows.Input.Key]$key
            $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($wpfKey)
            $ok = $script:Hotkey.Set([uint32]$script:Settings.HotkeyMods, [uint32]$vk)
        } catch { $ok = $false }
        if (-not $ok) { $ui.HotkeyMsg.Text = "$(Format-Hotkey) is already used by another program. Pick a different key." }
    }
    Update-PauseLabel
}

function Update-PauseLabel {
    $hk = if ($script:Settings.HotkeyKey) { " ($(Format-Hotkey))" } else { '' }
    if ($script:Paused) { $script:Ui.BtnPause.Content = "Paused - click to resume$hk" }
    else { $script:Ui.BtnPause.Content = "Pause (use the viewer)$hk" }
}

function New-Brush([string]$Hex) {
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze()
    $b
}

function Get-SetPoints([string]$Set) { @($script:Points | Where-Object { $_.Set -eq $Set } | Sort-Object Seq) }

function Get-OtherSet([string]$Set) { if ($Set -eq 'C') { 'A' } else { 'C' } }

# Fill the reference-length box in the chosen unit (stored value is always mm).
function Show-ReferenceLength {
    $script:Loading = $true
    try {
        if ($script:Settings.Units -eq 'in') {
            $script:Ui.LblRef.Text = 'Distance between C outside points (inches)'
            $script:Ui.TxtMm.Text = ([math]::Round([double]$script:Settings.OuterMm / 25.4, 3)).ToString()
        } else {
            $script:Ui.LblRef.Text = 'Distance between C outside points (mm)'
            $script:Ui.TxtMm.Text = ([math]::Round([double]$script:Settings.OuterMm, 2)).ToString()
        }
        $script:Ui.TxtMm.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
    } finally { $script:Loading = $false }
}

# Highlight the point under the mouse; redraw only when it changes.
function Set-Hover($Point) {
    if ([object]::ReferenceEquals($Point, $script:Hover)) { return }
    $script:Hover = $Point
    if ($Point) { $script:Canvas.Cursor = [System.Windows.Input.Cursors]::SizeAll }
    else { $script:Canvas.ClearValue([System.Windows.FrameworkElement]::CursorProperty) }
    Update-View
}

function Find-NearestPoint($Pos) {
    $radius = [math]::Max([double]$script:Settings.PointSize / 2 + 4, 8)
    $best = $null; $bestD = [double]::MaxValue
    foreach ($p in $script:Points) {
        $d = Get-Distance $p $Pos
        if ($d -le $radius -and $d -lt $bestD) { $best = $p; $bestD = $d }
    }
    $best
}

function Add-Point($Pos) {
    $set = $script:Active
    if ((Get-SetPoints $set).Count -ge 4) {
        $set = Get-OtherSet $set
        if ((Get-SetPoints $set).Count -ge 4) { return }   # both sets full: drag to adjust
    }
    $script:Seq++
    [void]$script:Points.Add([pscustomobject]@{ Set = $set; X = $Pos.X; Y = $Pos.Y; Seq = $script:Seq })
    $script:Active = $set
    if ((Get-SetPoints $set).Count -ge 4) {
        $other = Get-OtherSet $set
        if ((Get-SetPoints $other).Count -lt 4) { $script:Active = $other }
    }
    Update-View
}

function Undo-Point {
    if ($script:Points.Count -eq 0) { return }
    $last = $script:Points | Sort-Object Seq | Select-Object -Last 1
    $script:Points.Remove($last)
    $script:Active = $last.Set
    Update-View
}

function Clear-Set([string]$Set) {
    foreach ($p in @(Get-SetPoints $Set)) { $script:Points.Remove($p) }
    $script:Active = $Set
    Update-View
}

function Set-Paused([bool]$On) {
    $script:Paused = $On
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:Overlay).Handle
    $GWL_EXSTYLE = -20; $WS_EX_TRANSPARENT = 0x20
    $ex = [CATool.Native]::GetWindowLong($hwnd, $GWL_EXSTYLE)
    if ($On) { $ex = $ex -bor $WS_EX_TRANSPARENT } else { $ex = $ex -band (-bnot $WS_EX_TRANSPARENT) }
    [void][CATool.Native]::SetWindowLong($hwnd, $GWL_EXSTYLE, $ex)
    if ($On) {
        if ($null -ne $script:Drag) { $script:Drag = $null; $script:Canvas.ReleaseMouseCapture() }
        $script:Hover = $null
        $script:Canvas.Background = [System.Windows.Media.Brushes]::Transparent
    } else {
        $script:Canvas.Background = $script:CatchBrush
    }
    Update-PauseLabel
    $script:Ui.BtnPause.IsChecked = $On
    Update-View
}

function Add-Shape($Shape) {
    $Shape.IsHitTestVisible = $false
    [void]$script:Canvas.Children.Add($Shape)
}

function Add-CircleShape($Circle, $Brush, [double]$Thickness, [double]$Opacity) {
    if (-not $Circle -or $Circle.R -gt 20000) { return }
    $el = New-Object System.Windows.Shapes.Ellipse
    $el.Width = 2 * $Circle.R; $el.Height = 2 * $Circle.R
    $el.Stroke = $Brush; $el.StrokeThickness = $Thickness; $el.Opacity = $Opacity
    [System.Windows.Controls.Canvas]::SetLeft($el, $Circle.X - $Circle.R)
    [System.Windows.Controls.Canvas]::SetTop($el, $Circle.Y - $Circle.R)
    Add-Shape $el
}

function Update-View {
    $canvas = $script:Canvas
    $canvas.Children.Clear()
    $size = [double]$script:Settings.PointSize
    $black = [System.Windows.Media.Brushes]::Black
    $results = @{}

    foreach ($set in 'C', 'A') {
        $brush = New-Brush $script:Settings['Color' + $set]
        $pts = Get-SetPoints $set
        $res = Get-SetResult $pts
        $results[$set] = $res

        if ($res -and $script:Settings.ShowCircles) {
            Add-CircleShape $res.AvgCircle $brush 1.5 0.85
        }

        # Hover color: white, or yellow if the set itself is white.
        $hoverHex = if ($script:Settings['Color' + $set] -eq '#FFFFFF') { '#FFEB3B' } else { '#FFFFFF' }
        $hoverBrush = New-Brush $hoverHex

        foreach ($p in $pts) {
            $isHover = [object]::ReferenceEquals($p, $script:Hover) -or [object]::ReferenceEquals($p, $script:Drag)
            $pb = if ($isHover) { $hoverBrush } else { $brush }
            # dark halo for contrast on white bone, colored ring, small center dot for precision
            $halo = New-Object System.Windows.Shapes.Ellipse
            $halo.Width = $size + 3; $halo.Height = $size + 3
            $halo.Stroke = $black; $halo.StrokeThickness = 1.5; $halo.Opacity = 0.7
            [System.Windows.Controls.Canvas]::SetLeft($halo, $p.X - ($size + 3) / 2)
            [System.Windows.Controls.Canvas]::SetTop($halo, $p.Y - ($size + 3) / 2)
            Add-Shape $halo

            $ring = New-Object System.Windows.Shapes.Ellipse
            $ring.Width = $size; $ring.Height = $size
            $ring.Stroke = $pb; $ring.StrokeThickness = [math]::Max(2, $size / 6)
            if ($isHover) { $ring.StrokeThickness += 1 }
            [System.Windows.Controls.Canvas]::SetLeft($ring, $p.X - $size / 2)
            [System.Windows.Controls.Canvas]::SetTop($ring, $p.Y - $size / 2)
            Add-Shape $ring

            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 3; $dot.Height = 3; $dot.Fill = $pb
            [System.Windows.Controls.Canvas]::SetLeft($dot, $p.X - 1.5)
            [System.Windows.Controls.Canvas]::SetTop($dot, $p.Y - 1.5)
            Add-Shape $dot

            $label = New-Object System.Windows.Controls.TextBlock
            $label.Text = $set
            $label.Foreground = $pb
            $label.FontWeight = 'Bold'
            $label.FontSize = [math]::Max(11, $size * 0.8)
            [System.Windows.Controls.Canvas]::SetLeft($label, $p.X + $size / 2 + 2)
            [System.Windows.Controls.Canvas]::SetTop($label, $p.Y - $size / 2 - $label.FontSize)
            Add-Shape $label
        }
    }

    Update-Toolbox $results
}

# A length given in mm, shown in the chosen unit.
function Format-Length([double]$Mm) {
    if ($script:Settings.Units -eq 'mm') { '{0:N1} mm' -f $Mm } else { '{0:N2} in' -f ($Mm / 25.4) }
}

function Update-Toolbox($Results) {
    $ui = $script:Ui
    $nC = (Get-SetPoints 'C').Count
    $nA = (Get-SetPoints 'A').Count
    $ui.TxtC.Text = "C  $nC/4"
    $ui.TxtA.Text = "A  $nA/4"
    $ui.BtnC.IsChecked = ($script:Active -eq 'C')
    $ui.BtnA.IsChecked = ($script:Active -eq 'A')
    $ui.SwC.Fill = New-Brush $script:Settings.ColorC
    $ui.SwA.Fill = New-Brush $script:Settings.ColorA

    foreach ($set in 'C', 'A') {
        foreach ($b in $ui['Pal' + $set].Children) {
            $selected = ([string]$b.Tag).EndsWith('|' + $script:Settings['Color' + $set])
            if ($selected) { $b.BorderThickness = New-Object System.Windows.Thickness 3; $b.BorderBrush = [System.Windows.Media.Brushes]::Black }
            else { $b.BorderThickness = New-Object System.Windows.Thickness 1; $b.BorderBrush = [System.Windows.Media.Brushes]::Gray }
        }
    }

    $dash = [string][char]0x2014
    $rc = $Results['C']; $ra = $Results['A']
    $mmPerUnit = $null
    if ($rc -and $rc.OuterDist -gt 0) { $mmPerUnit = [double]$script:Settings.OuterMm / $rc.OuterDist }

    if (-not $rc) { $ui.ValC.Text = $dash }
    elseif ($null -eq $rc.AvgDiam) { $ui.ValC.Text = 'points in a line' }
    else { $ui.ValC.Text = Format-Length ($rc.AvgDiam * $mmPerUnit) }

    if (-not $ra) { $ui.ValA.Text = $dash }
    elseif ($null -eq $ra.AvgDiam) { $ui.ValA.Text = 'points in a line' }
    elseif ($null -eq $mmPerUnit) { $ui.ValA.Text = 'needs C' }
    else { $ui.ValA.Text = Format-Length ($ra.AvgDiam * $mmPerUnit) }

    if ($rc -and $ra -and $rc.AvgDiam -and $ra.AvgDiam) { $ui.ValR.Text = '{0:N3}' -f ($rc.AvgDiam / $ra.AvgDiam) }
    else { $ui.ValR.Text = $dash }

    if ($script:Paused) {
        $ui.Hint.Text = 'Paused: clicks go to the image viewer. If you zoom or move the image, the points will no longer line up - clear and re-place them.'
    } elseif ($nC -lt 4 -or $nA -lt 4) {
        $n = (Get-SetPoints $script:Active).Count + 1
        $ui.Hint.Text = "Click to place $($script:Active) point $n of 4, in any order. Hover over a point to highlight it, then drag to move it; right-click deletes it."
    } else {
        $ui.Hint.Text = 'Both sets placed. Hover over any point, then drag to fine-tune it.'
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if ($env:CATOOL_NO_GUI -ne '1') {
    try {
        Start-CATool
    } catch {
        Write-ErrorLog $_.ToString()
        try {
            Add-Type -AssemblyName PresentationFramework
            [void][System.Windows.MessageBox]::Show("C/A Tool could not start:`n`n$($_.Exception.Message)`n`nDetails were saved to $script:LogPath", 'C/A Tool')
        } catch { }
    }
}
