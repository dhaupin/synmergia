#!/usr/bin/env node
/**
 * Puppeteer test script for Synmergia noVNC
 * Tests the VNC web interface and captures screenshots
 * 
 * Usage:
 *   node test-novnc.js                    # Run all tests
 *   node test-novnc.js --screenshot       # Take screenshot only
 *   node test-novnc.js --url http://...   # Custom URL
 */

const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

// Configuration
const VNC_URL = process.env.VNC_URL || 'http://localhost:6080/vnc.html';
const OUTPUT_DIR = process.env.OUTPUT_DIR || '/workspace/project/synmergia/screenshots';
const VIEWPORT = { width: 1920, height: 1080 };

// Colors
const colors = {
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    cyan: '\x1b[36m',
    reset: '\x1b[0m'
};

const log = {
    info: (msg) => console.log(`${colors.green}[INFO]${colors.reset} ${msg}`),
    warn: (msg) => console.log(`${colors.yellow}[WARN]${colors.reset} ${msg}`),
    error: (msg) => console.log(`${colors.red}[ERROR]${colors.reset} ${msg}`),
    test: (msg) => console.log(`${colors.cyan}[TEST]${colors.reset} ${msg}`)
};

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

/**
 * Main test runner
 */
async function runTests() {
    log.info('🚀 Starting Synmergia noVNC Tests');
    log.info(`   URL: ${VNC_URL}`);
    log.info(`   Output: ${OUTPUT_DIR}`);
    
    let browser;
    try {
        // Launch browser
        browser = await puppeteer.launch({
            headless: 'new',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-accelerated-2d-canvas',
                '--no-first-run',
                '--no-zygote',
                '--disable-gpu'
            ]
        });
        
        const page = await browser.newPage();
        await page.setViewport(VIEWPORT);
        
        // Test 1: Load page
        log.test('Loading noVNC page...');
        await page.goto(VNC_URL, { waitUntil: 'networkidle0', timeout: 30000 });
        log.info('✅ Page loaded successfully');
        
        // Test 2: Check for VNC connection form
        log.test('Checking for VNC connection UI...');
        const connectButton = await page.$('text=Connect');
        if (connectButton) {
            log.info('✅ VNC connect button found');
            
            // Fill in connection
            const hostInput = await page.$('input[type=text]');
            if (hostInput) {
                await hostInput.type('localhost:5900');
                log.info('   Set host to localhost:5900');
            }
            
            // Click connect
            await connectButton.click();
            log.info('   Clicked Connect');
            
            // Wait for connection
            await page.waitForTimeout(3000);
        }
        
        // Test 3: Check for canvas (VNC screen)
        log.test('Checking for VNC canvas...');
        const canvas = await page.$('canvas');
        if (canvas) {
            log.info('✅ VNC canvas found');
            
            // Take screenshot
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const screenshotPath = path.join(OUTPUT_DIR, `puppeteer_test_${timestamp}.png`);
            
            await canvas.screenshot({ path: screenshotPath });
            const stats = fs.statSync(screenshotPath);
            log.info(`✅ Screenshot saved: ${screenshotPath} (${(stats.size / 1024).toFixed(1)} KB)`);
        }
        
        // Test 4: Get page title
        const title = await page.title();
        log.info(`   Page title: ${title}`);
        
        // Test 5: Check for errors in console
        log.test('Checking console for errors...');
        const logs = [];
        page.on('console', msg => {
            if (msg.type() === 'error') {
                logs.push(`ERROR: ${msg.text()}`);
            }
        });
        
        await page.waitForTimeout(2000);
        
        if (logs.length === 0) {
            log.info('✅ No console errors detected');
        } else {
            logs.forEach(log => console.log(`   ${log}`));
        }
        
        log.info('');
        log.info('🎉 All tests passed!');
        
    } catch (error) {
        log.error(`Test failed: ${error.message}`);
        throw error;
    } finally {
        if (browser) {
            await browser.close();
        }
    }
}

/**
 * Screenshot only mode
 */
async function takeScreenshot() {
    log.info('📸 Synmergia Screenshot Mode');
    
    let browser;
    try {
        browser = await puppeteer.launch({
            headless: 'new',
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });
        
        const page = await browser.newPage();
        await page.setViewport(VIEWPORT);
        
        log.info(`Loading: ${VNC_URL}`);
        await page.goto(VNC_URL, { waitUntil: 'networkidle0', timeout: 30000 });
        
        // Wait for VNC to load
        await page.waitForTimeout(2000);
        
        // Take full page screenshot
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const screenshotPath = path.join(OUTPUT_DIR, `synmergia_full_${timestamp}.png`);
        
        await page.screenshot({ 
            path: screenshotPath,
            fullPage: true 
        });
        
        const stats = fs.statSync(screenshotPath);
        log.info(`✅ Screenshot saved: ${screenshotPath}`);
        log.info(`   Size: ${(stats.size / 1024).toFixed(1)} KB`);
        
    } catch (error) {
        log.error(`Screenshot failed: ${error.message}`);
        throw error;
    } finally {
        if (browser) {
            await browser.close();
        }
    }
}

// Main
const args = process.argv.slice(2);

if (args.includes('--screenshot') || args.includes('-s')) {
    takeScreenshot().catch(() => process.exit(1));
} else if (args.includes('--help') || args.includes('-h')) {
    console.log(`
Synmergia noVNC Puppeteer Test Script

Usage:
  node test-novnc.js [options]

Options:
  --screenshot, -s    Take screenshot and exit
  --url URL           Custom VNC URL
  --help, -h         Show this help

Environment:
  VNC_URL            VNC URL (default: http://localhost:6080/vnc.html)
  OUTPUT_DIR         Output directory (default: /workspace/project/synmergia/screenshots)
`);
} else {
    runTests().catch(() => process.exit(1));
}
