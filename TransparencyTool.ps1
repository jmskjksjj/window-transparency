# =====================================================================
#  투명도 유틸리티 (Windows 11) - Malgun Gothic + 자간 적용
#    - Finder(과녁) 드래그로 대상 창 선택  (아이콘은 GDI+ 직접 드로잉)
#    - 같은 창에 다시 놓으면 그 창만 복원 (토글)
#    - 슬라이더로 불투명도(5~100%) 실시간 적용
#    - 모든 텍스트: Malgun Gothic, GDI SetTextCharacterExtra 로 자간 +1px
#  Win32 SetLayeredWindowAttributes 사용, 별도 설치 불필요
# =====================================================================

# --- WinForms 는 STA 스레드 필요 → .ps1 로 직접 실행됐고 STA 가 아니면 재실행 ---
#     (exe 로 빌드된 경우엔 -STA 로 컴파일되므로 이 블록은 건너뜀)
if (($PSCommandPath -like '*.ps1') -and ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
    $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $exe) { $exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    Start-Process -FilePath $exe -ArgumentList @(
        '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`""
    )
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 네이티브 Win32 API (레이어드 윈도우 + GDI 텍스트 자간) ---
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE  { public int cx; public int cy; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flag);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    // --- GDI: 자간 텍스트 출력 ---
    [DllImport("gdi32.dll")] public static extern int SetTextCharacterExtra(IntPtr hdc, int extra);
    [DllImport("gdi32.dll")] public static extern int SetBkMode(IntPtr hdc, int mode);
    [DllImport("gdi32.dll")] public static extern uint SetTextColor(IntPtr hdc, uint color);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern bool TextOut(IntPtr hdc, int x, int y, string s, int len);
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern bool GetTextExtentPoint32(IntPtr hdc, string s, int len, out SIZE sz);
}
'@

$GWL_EXSTYLE   = -20
$WS_EX_LAYERED = 0x80000
$LWA_ALPHA     = 0x2
$GA_ROOT       = 2
$FONT_NAME     = 'Malgun Gothic'   # 모든 Windows 10/11 기본 내장 (한글 가독성 좋음)
$LETTER_EXTRA  = 0                  # 자간 추가 px (0 = 원래대로)

# 콘솔(검은 창) 숨기기 - GUI만 표시
$cw = [Win]::GetConsoleWindow()
if ($cw -ne [IntPtr]::Zero) { [void][Win]::ShowWindow($cw, 0) }

$script:Target   = [IntPtr]::Zero
$script:Modified = @{}
$script:Picking  = $false
$script:Pct      = 75
$script:TgtText  = '선택된 창 없음'
$script:TgtColor = $null            # 아래에서 색상 정의 후 설정

# --- 자간 적용 텍스트 렌더링 (GDI SetTextCharacterExtra) ---
function DrawSpaced {
    param($g, [string[]]$lines, $font, $color, [int]$spacing, [int]$boxW, [int]$boxH, [string]$align)
    $lineH  = $font.Height
    $totalH = $lineH * $lines.Count
    $startY = [int](($boxH - $totalH) / 2.0); if ($startY -lt 0) { $startY = 0 }
    $hdc = $g.GetHdc()
    try {
        $hf  = $font.ToHfont()
        $old = [Win]::SelectObject($hdc, $hf)
        [void][Win]::SetBkMode($hdc, 1)   # TRANSPARENT
        $bgr = [uint32]([int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16))
        [void][Win]::SetTextColor($hdc, $bgr)
        [void][Win]::SetTextCharacterExtra($hdc, $spacing)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = [string]$lines[$i]
            if ($align -eq 'center') {
                $sz = New-Object Win+SIZE
                [void][Win]::GetTextExtentPoint32($hdc, $ln, $ln.Length, [ref]$sz)
                $lineW = $sz.cx + ($spacing * $ln.Length)
                $x = [int](($boxW - $lineW) / 2.0); if ($x -lt 0) { $x = 0 }
            } else { $x = 0 }
            [void][Win]::TextOut($hdc, $x, ($startY + $i * $lineH), $ln, $ln.Length)
        }
        [void][Win]::SelectObject($hdc, $old)
        [void][Win]::DeleteObject($hf)
    } finally { $g.ReleaseHdc($hdc) }
}

function Get-WinTitle([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return '' }
    $sb = New-Object System.Text.StringBuilder 512
    [void][Win]::GetWindowText($h, $sb, 512)
    $t = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($t)) {
        $cb = New-Object System.Text.StringBuilder 256
        [void][Win]::GetClassName($h, $cb, 256)
        $t = "[$($cb.ToString())]"
    }
    return $t
}

function Get-RootUnderCursor {
    $p = New-Object Win+POINT
    [void][Win]::GetCursorPos([ref]$p)
    $h = [Win]::WindowFromPoint($p)
    if ($h -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
    return [Win]::GetAncestor($h, $GA_ROOT)
}

function Set-Opacity([IntPtr]$h, [int]$percent) {
    if ($h -eq [IntPtr]::Zero -or -not [Win]::IsWindow($h)) { return $false }
    $alpha = [byte][math]::Round($percent * 255.0 / 100.0)
    $ex = [Win]::GetWindowLong($h, $GWL_EXSTYLE)
    if (($ex -band $WS_EX_LAYERED) -eq 0) {
        [void][Win]::SetWindowLong($h, $GWL_EXSTYLE, ($ex -bor $WS_EX_LAYERED))
    }
    $ok = [Win]::SetLayeredWindowAttributes($h, 0, $alpha, $LWA_ALPHA)
    if ($ok) { $script:Modified[[int64]$h] = $h }
    return $ok
}

function Restore-One([IntPtr]$h) {
    if ([Win]::IsWindow($h)) { [void][Win]::SetLayeredWindowAttributes($h, 0, 255, $LWA_ALPHA) }
    [void]$script:Modified.Remove([int64]$h)
    if ($script:Target -eq $h) { $script:Target = [IntPtr]::Zero }
}

# ---------------- UI ----------------
[System.Windows.Forms.Application]::EnableVisualStyles()

$COL_BG     = [System.Drawing.Color]::White
$COL_TEXT   = [System.Drawing.Color]::FromArgb(26, 26, 26)
$COL_SUB    = [System.Drawing.Color]::FromArgb(105, 105, 105)
$COL_LINE   = [System.Drawing.Color]::FromArgb(206, 206, 206)
$COL_ACCENT = [System.Drawing.Color]::FromArgb(0, 103, 192)
$COL_ERR    = [System.Drawing.Color]::FromArgb(196, 43, 28)
$script:TgtColor = $COL_SUB

$FONT_BASE = New-Object System.Drawing.Font($FONT_NAME, 8.5)
$FONT_PCT  = New-Object System.Drawing.Font($FONT_NAME, 13)

# 더블버퍼링 헬퍼
$DBProp = [System.Windows.Forms.Control].GetProperty('DoubleBuffered',
    [System.Reflection.BindingFlags]'Instance,NonPublic')
function EnableDB($c) { if ($DBProp) { $DBProp.SetValue($c, $true, $null) } }

$form = New-Object System.Windows.Forms.Form
$form.Text = '창 투명도 조절기'
$form.Font = $FONT_BASE
$form.ClientSize = New-Object System.Drawing.Size(308, 145)
$form.BackColor = $COL_BG
$form.FormBorderStyle = 'FixedSingle'   # 타이틀바 아이콘 표시 (FixedDialog 는 아이콘 숨김)
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.ShowIcon = $true

# 타이틀바/작업표시줄 아이콘: exe 에 박힌 아이콘을 창에 직접 지정
# (파일명 무관 - PowerShell 호스트로 .ps1 직접 실행할 때만 제외)
try {
    $exeSelf = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $leaf = [System.IO.Path]::GetFileName($exeSelf).ToLower()
    if ($leaf -ne 'powershell.exe' -and $leaf -ne 'pwsh.exe') {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exeSelf)
    }
} catch { }

# ---- Finder 과녁 ----
$finder = New-Object System.Windows.Forms.Panel
$finder.SetBounds(15, 11, 50, 50)
$finder.BackColor = $COL_BG
$finder.Cursor = [System.Windows.Forms.Cursors]::Cross
EnableDB $finder
$form.Controls.Add($finder)

$finder.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $c = if ($script:Picking) { $COL_ACCENT } else { $COL_TEXT }
    $pen = New-Object System.Drawing.Pen($c, 2)
    $cx = $s.Width / 2.0; $cy = $s.Height / 2.0
    $r  = ([math]::Min($s.Width, $s.Height) / 2.0) - 6
    $g.DrawEllipse($pen, [single]($cx-$r), [single]($cy-$r), [single](2*$r), [single](2*$r))
    foreach ($a in 0, 90, 180, 270) {
        $rad = $a * [math]::PI / 180.0
        $x1 = $cx + [math]::Cos($rad) * ($r - 4); $y1 = $cy + [math]::Sin($rad) * ($r - 4)
        $x2 = $cx + [math]::Cos($rad) * ($r + 4); $y2 = $cy + [math]::Sin($rad) * ($r + 4)
        $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
    }
    $br = New-Object System.Drawing.SolidBrush($c)
    $g.FillEllipse($br, [single]($cx-2.5), [single]($cy-2.5), 5.0, 5.0)
    $pen.Dispose(); $br.Dispose()
})

# ---- 사용법 (자간 적용) ----
$helpLines = @(
    '1. 과녁을 끌어 창 위에 놓기 (투명 적용)',
    '2. 같은 창에 다시 놓기 (복원)',
    '3. 슬라이더로 투명도 조절'
)
$pnlHelp = New-Object System.Windows.Forms.Panel
$pnlHelp.SetBounds(73, 9, 227, 50)
$pnlHelp.BackColor = $COL_BG
EnableDB $pnlHelp
$form.Controls.Add($pnlHelp)
$pnlHelp.Add_Paint({ param($s, $e) DrawSpaced $e.Graphics $helpLines $FONT_BASE $COL_SUB $LETTER_EXTRA $s.Width $s.Height 'left' })

# ---- 대상 창 상태 (동적, 자간 적용) ----
$pnlTarget = New-Object System.Windows.Forms.Panel
$pnlTarget.SetBounds(15, 60, 277, 18)
$pnlTarget.BackColor = $COL_BG
EnableDB $pnlTarget
$form.Controls.Add($pnlTarget)
$pnlTarget.Add_Paint({ param($s, $e) DrawSpaced $e.Graphics @($script:TgtText) $FONT_BASE $script:TgtColor $LETTER_EXTRA $s.Width $s.Height 'center' })

# ---- % (동적, 자간 적용) ----
$pnlPct = New-Object System.Windows.Forms.Panel
$pnlPct.SetBounds(11, 80, 51, 26)
$pnlPct.BackColor = $COL_BG
EnableDB $pnlPct
$form.Controls.Add($pnlPct)
$pnlPct.Add_Paint({ param($s, $e) DrawSpaced $e.Graphics @("$($script:Pct)%") $FONT_PCT $COL_TEXT $LETTER_EXTRA $s.Width $s.Height 'center' })

# ---- 슬라이더 ----
$bar = New-Object System.Windows.Forms.TrackBar
$bar.AutoSize = $false
$bar.Minimum = 5; $bar.Maximum = 100; $bar.Value = 75
$bar.TickStyle = 'None'
$bar.SmallChange = 1; $bar.LargeChange = 10
$bar.BackColor = $COL_BG
$bar.SetBounds(64, 84, 233, 26)
$form.Controls.Add($bar)

# ---- 플랫 버튼 (테두리 + 자간 텍스트 직접 드로잉) ----
function New-FlatButton($text, $x, $y, $w, $h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Tag = $text
    $b.Text = ''
    $b.SetBounds($x, $y, $w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $b.BackColor = $COL_BG
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    EnableDB $b
    $b.Add_Paint({
        param($s, $e)
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $pen = New-Object System.Drawing.Pen($COL_LINE, 1)
        $e.Graphics.DrawRectangle($pen, $rect); $pen.Dispose()
        DrawSpaced $e.Graphics @([string]$s.Tag) $FONT_BASE $COL_TEXT $LETTER_EXTRA $s.Width $s.Height 'center'
    })
    return $b
}

$btnRestore = New-FlatButton '모두 복원' 13 114 136 24
$form.Controls.Add($btnRestore)
$btnClose = New-FlatButton '닫기' 158 114 136 24
$form.Controls.Add($btnClose)

# 레이어 순서: 슬라이더 뒤로, 버튼 앞으로
$bar.SendToBack()
$btnRestore.BringToFront()
$btnClose.BringToFront()

# ---------------- 이벤트 ----------------
$finder.Add_MouseDown({ $script:Picking = $true; $finder.Invalidate() })

$finder.Add_MouseMove({
    if (-not $script:Picking) { return }
    $h = Get-RootUnderCursor
    if ($h -ne $form.Handle -and $h -ne [IntPtr]::Zero) {
        $script:TgtColor = $COL_SUB
        if ($script:Modified.ContainsKey([int64]$h)) {
            $script:TgtText = '놓으면 복원: ' + (Get-WinTitle $h)
        } else {
            $script:TgtText = '놓으면 적용: ' + (Get-WinTitle $h)
        }
        $pnlTarget.Invalidate()
    }
})

$finder.Add_MouseUp({
    if (-not $script:Picking) { return }
    $script:Picking = $false
    $finder.Invalidate()
    $h = Get-RootUnderCursor
    if ($h -eq [IntPtr]::Zero -or $h -eq $form.Handle) {
        $script:TgtColor = $COL_SUB; $script:TgtText = '선택된 창 없음'; $pnlTarget.Invalidate(); return
    }
    if ($script:Modified.ContainsKey([int64]$h)) {
        Restore-One $h
        $script:TgtColor = $COL_SUB; $script:TgtText = '복원됨: ' + (Get-WinTitle $h)
    } else {
        $script:Target = $h
        if (Set-Opacity $h $script:Pct) {
            $script:TgtColor = $COL_TEXT; $script:TgtText = '적용됨: ' + (Get-WinTitle $h)
        } else {
            $script:TgtColor = $COL_ERR; $script:TgtText = '적용 실패 - 관리자 권한 창'
        }
    }
    $pnlTarget.Invalidate()
})

$bar.Add_ValueChanged({
    $script:Pct = $bar.Value
    $pnlPct.Invalidate()
    if ($script:Target -ne [IntPtr]::Zero) { [void](Set-Opacity $script:Target $bar.Value) }
})

$btnRestore.Add_Click({
    foreach ($h in @($script:Modified.Values)) {
        if ([Win]::IsWindow($h)) { [void][Win]::SetLayeredWindowAttributes($h, 0, 255, $LWA_ALPHA) }
    }
    $script:Modified.Clear()
    $script:Target = [IntPtr]::Zero
    $script:TgtColor = $COL_SUB; $script:TgtText = '선택된 창 없음'; $pnlTarget.Invalidate()
    $bar.Value = 100
})

$btnClose.Add_Click({ $form.Close() })

$form.Add_Shown({ $bar.Focus() })

[void]$form.ShowDialog()
$form.Dispose()
