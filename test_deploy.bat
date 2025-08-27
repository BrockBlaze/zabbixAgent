@echo off
echo ==========================================
echo  Testing Rithm Clean Installer
echo ==========================================
echo.

echo Testing connectivity first...
ping -n 1 192.168.68.146 >nul 2>&1
if %errorlevel%==0 (
    echo [OK] Arc ^(192.168.68.146^) is reachable
) else (
    echo [ERROR] Cannot reach Arc ^(192.168.68.146^)
    exit /b 1
)

ping -n 1 192.168.70.35 >nul 2>&1
if %errorlevel%==0 (
    echo [OK] Cobalt ^(192.168.70.35^) is reachable
) else (
    echo [ERROR] Cannot reach Cobalt ^(192.168.70.35^)
    exit /b 1
)

echo.
echo ==========================================
echo Ready to deploy! 
echo ==========================================
echo.
echo Manual commands to run:
echo.
echo 1. For Arc ^(192.168.68.146^):
echo    ssh root@192.168.68.146
echo    # Copy install_clean.sh to server, then:
echo    chmod +x install_clean.sh
echo    sudo ZABBIX_SERVER=192.168.70.2 HOSTNAME=Arc ./install_clean.sh
echo.
echo 2. For Cobalt ^(192.168.70.35^):
echo    ssh root@192.168.70.35
echo    # Copy install_clean.sh to server, then:
echo    chmod +x install_clean.sh
echo    sudo ZABBIX_SERVER=192.168.70.2 HOSTNAME=Cobalt ./install_clean.sh
echo.
echo 3. Import Template_Rithm_Custom.json to Zabbix
echo.
echo 4. Test from Zabbix server:
echo    zabbix_get -s 192.168.68.146 -k custom.cpu.temperature
echo    zabbix_get -s 192.168.70.35 -k custom.memory.available
echo.
pause