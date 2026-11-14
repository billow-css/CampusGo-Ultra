; Shared with src/access.rs. Presence of Blocked, of any type, denies installation.
; This key is deliberately separate from NSIS uninstall metadata.
Function CampusGoAccessCheck
  Push $R0
  Push $R1
  SetRegView 64
  StrCpy $R0 0
  campusgo_access_loop:
    ClearErrors
    EnumRegValue $R1 HKCU "Software\CampusGoUltra\AccessControl" $R0
    IfErrors campusgo_access_done
    StrCmp $R1 "Blocked" campusgo_access_denied
    IntOp $R0 $R0 + 1
    Goto campusgo_access_loop
  campusgo_access_denied:
    MessageBox MB_OK|MB_ICONSTOP "你已被开发者拉入黑名单，请及时联系开发者。无法继续安装 CampusGo Ultra。" /SD IDOK
    SetErrorLevel 77
    Quit
  campusgo_access_done:
    Pop $R1
    Pop $R0
FunctionEnd

!define MUI_CUSTOMFUNCTION_GUIINIT CampusGoAccessCheck

!macro NSIS_HOOK_PREINSTALL
  ; Also covers silent installers, which do not run the GUI initialization hook.
  Call CampusGoAccessCheck
!macroend
