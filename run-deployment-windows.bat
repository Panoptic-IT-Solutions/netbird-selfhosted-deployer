@echo off
REM NetBird Windows Deployment Runner
REM This script runs the NetBird deployment using Docker on Windows

echo ╔═══════════════════════════════════════════════════════════════╗
echo ║                                                               ║
echo ║        🚀 NetBird Windows Deployment Runner                  ║
echo ║                                                               ║
echo ║        Running deployment script via Docker container        ║
echo ║                                                               ║
echo ╚═══════════════════════════════════════════════════════════════╝
echo.

REM Check if Docker is installed
docker --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Docker is not installed or not in PATH
    echo.
    echo Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/
    echo.
    pause
    exit /b 1
)

echo [INFO] Docker found, building deployment container...
echo.

REM Build the Docker image
docker build -t netbird-deployer docker-runner/
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to build Docker image
    pause
    exit /b 1
)

echo.
echo [INFO] Container built successfully!
echo.
echo [INFO] Starting interactive deployment session...
echo [INFO] You will be dropped into a bash shell where you can run:
echo [INFO]   ./deploy-netbird-selfhosted.sh
echo.
echo [WARNING] Make sure you have configured your Hetzner Cloud API token first:
echo [WARNING]   hcloud context create myproject
echo.

REM Run the container interactively
docker run -it --rm ^
    -v "%CD%":/netbird ^
    -v "%USERPROFILE%\.ssh":/root/.ssh:ro ^
    -v "%USERPROFILE%\.config\hcloud":/root/.config/hcloud ^
    netbird-deployer

echo.
echo [INFO] Deployment session ended.
pause
