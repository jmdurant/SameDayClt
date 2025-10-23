"""Test if ChromeDriver is working"""
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
import time
import os

print("Checking chromedriver.exe exists...")
driver_path = "./chromedriver.exe"
if os.path.exists(driver_path):
    print(f"[SUCCESS] Found chromedriver.exe at {driver_path}")
else:
    print(f"[ERROR] chromedriver.exe not found at {driver_path}")
    exit(1)

print("Setting up Chrome service...")
service = Service(driver_path)

print("Configuring Chrome options (headless mode)...")
options = webdriver.ChromeOptions()
options.add_argument('--headless')
options.add_argument('--no-sandbox')
options.add_argument('--disable-dev-shm-usage')
options.add_argument('--disable-gpu')

print("Starting Chrome browser...")
driver = webdriver.Chrome(service=service, options=options)
print("[SUCCESS] Chrome started successfully!")

print("Navigating to Google...")
driver.get("https://www.google.com")
print(f"[SUCCESS] Page title: {driver.title}")

time.sleep(1)
print("Closing browser...")
driver.quit()
print("[SUCCESS] Test complete!")
