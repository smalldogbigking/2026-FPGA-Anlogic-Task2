@echo off
cd /d "%~dp0"
python fpga\prepare_project.py
if errorlevel 1 (
  pause
  exit /b 1
)
start "" "fpga\td_project\latest_plus_v3_hdmi_capture.al"
