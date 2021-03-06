!include MUI2.nsh

!system "readVersion.exe"
!include "Version.txt"

; install in program files
installDir $PROGRAMFILES\dancerm

requestExecutionLevel admin

; generated file and name
Name "DanceRM - v${Version}"
outFile "DanceRM-installer-${Version}.exe"

!define LANG_FRENCH "French"

; header customization
!define MUI_HEADERIMAGE
!define MUI_BGCOLOR "ffffff"
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_ICON "..\app\style\img\dancerm.ico"

; displayed pages: choose directory, and file installation
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; default section
section

  ; define the output path files
  setOutPath $INSTDIR
  file ..\package.json

  setOutPath $INSTDIR\bin
  file /r ..\bin\*.*

  setOutPath $INSTDIR\app
  file /r ..\app\*.*

  setOutPath $INSTDIR\node_modules
  file /r ..\node_modules\*.*

  ; grant permission for writing
  AccessControl::GrantOnFile "$LOCALAPPDATA\dancerm" "(BU)" "GenericRead + GenericWrite"
  AccessControl::GrantOnFile "$INSTDIR" "(BU)" "FullAccess"

  ; creates a shortcut within installation folder and on desktop
  createShortCut "$INSTDIR\DanceRM.lnk" "$INSTDIR\bin\nw.exe" '"$INSTDIR"' "$INSTDIR\app\style\img\dancerm.ico"
  createShortCut "$DESKTOP\DanceRM.lnk" "$INSTDIR\bin\nw.exe" '"$INSTDIR"' "$INSTDIR\app\style\img\dancerm.ico"

  ; Write also the uninstaller
  writeUninstaller $INSTDIR\uninstall.exe

sectionEnd

; uninstallation pages: confirm and file deletion
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Uninstall section
section "Uninstall"

  ; Always delete uninstaller first
  delete $INSTDIR\uninstall.exe
  delete $INSTDIR\package.json
  delete $INSTDIR\README.md
  rmdir /r $INSTDIR\app
  rmdir /r $INSTDIR\bin
  rmdir /r $INSTDIR\node_modules
  delete $INSTDIR\DanceRM.lnk
  delete $DESKTOP\DanceRM.lnk

sectionEnd

; language labels
!define MUI_TEXT_WELCOME_INFO_TITLE "Bienvenue dans l'installation de l'application $(^NameDA)."
!define MUI_TEXT_WELCOME_INFO_TEXT "Vous �tes sur le point d'installer $(^NameDA) sur votre ordinateur.$\r$\n$\r$\n$_CLICK"
!insertmacro MUI_LANGUAGE ${LANG_FRENCH}