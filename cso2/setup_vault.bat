@echo off
SETLOCAL EnableDelayedExpansion

echo ========================================================
echo   CSO2 ZERO TRUST SECURITY SETUP (HashiCorp Vault)
echo   Automated Secret Injection for Team CSO2
echo ========================================================
echo.

:: --- 1. PRE-FLIGHT CHECK ---
if not exist "docker-compose.yml" (
    echo [ERROR] docker-compose.yml not found!
    echo Please ensure this file is in the same folder as docker-compose.yml.
    pause
    exit /b
)

:: --- 2. START INFRASTRUCTURE ---
echo [1/5] Starting Docker Containers...
docker-compose up -d
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker failed to start. Is Docker Desktop running?
    pause
    exit /b
)

echo.
echo [INFO] Waiting 15 seconds for Vault to wake up...
timeout /t 15 /nobreak >nul

:: --- 3. CONFIGURE VAULT ---
echo.
echo [2/5] Enabling Vault Storage...
docker exec -it cli-vault sh -c "vault login my-root-token > /dev/null 2>&1"
docker exec -it cli-vault sh -c "vault secrets enable -version=2 -path=kv kv > /dev/null 2>&1"

:: --- 4. DEFINE SECRETS ---
echo.
echo [3/5] Preparing Secrets...

:: A. Database Credentials (Shared)
set "SECRETS=db_username=cso2 db_password=password123"

:: B. Redis (Cache)
set "SECRETS=!SECRETS! redis_host=localhost redis_port=6379"

:: C. MongoDB Connection Strings
set "SECRETS=!SECRETS! mongodb_uri=mongodb://localhost:27017/CSO2_shoppingcart_wishlist_service"
set "SECRETS=!SECRETS! product_mongodb_uri=mongodb://localhost:27017/CSO2_product_catalogue_service"
set "SECRETS=!SECRETS! content_mongodb_uri=mongodb://localhost:27017/CSO2_content_service"
set "SECRETS=!SECRETS! notifications_mongodb_uri=mongodb://localhost:27017/CSO2_notifications_service"
set "SECRETS=!SECRETS! support_mongodb_uri=mongodb://localhost:27017/CSO2_support_service"

:: D. Notification Credentials (PLACEHOLDERS)
:: NOTE: If you need to test email sending locally, open this file 
:: and replace these two values with your real Gmail App Password.
set "SECRETS=!SECRETS! mail_username=user@example.com"
set "SECRETS=!SECRETS! mail_password=change_me_locally"

:: E. Twilio Credentials (PLACEHOLDERS — replace with real values to test SMS)
set "SECRETS=!SECRETS! twilio_account_sid=change_me_locally"
set "SECRETS=!SECRETS! twilio_auth_token=change_me_locally"
set "SECRETS=!SECRETS! twilio_phone_number=change_me_locally"

:: F. AI / Gemini API Key (PLACEHOLDER — replace with your real Google Gemini API key)
set "SECRETS=!SECRETS! gemini_api_key=change_me_locally"

:: --- 5. INJECT SECRETS ---
echo.
echo [4/5] Injecting Secrets into 'kv/cs02-app'...
docker exec -it cli-vault sh -c "vault kv put kv/cs02-app !SECRETS!"

if %ERRORLEVEL% EQU 0 (
    echo    - Success: Secrets injected.
) else (
    echo    - [ERROR] Failed to inject secrets.
)

:: --- 6. APPLY POLICY ---
echo.
echo [5/5] Applying Read-Only Policy...
docker exec -it cli-vault sh -c "echo 'path \"kv/data/cs02-app\" { capabilities = [\"read\"] }' | vault policy write user-policy -"

echo.
echo ========================================================
echo   SETUP COMPLETE!
echo   1. Infrastructure is running.
echo   2. Secrets are live in Vault.
echo   3. You can now start your Microservices.
echo ========================================================
echo.
pause