#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { AbiCoder } = require('ethers');

// Configuration
const BROADCAST_DIR = './broadcast';
const COMPILER_VERSION = '0.8.23';
const DEFAULT_RPC_URL = 'base';

// Network chain ID mappings
const NETWORK_CHAIN_IDS = {
    'mainnet': '1',
    'ethereum': '1',
    'base': '8453',
    'base_sepolia': '84532',
    'sepolia': '11155111',
    'ethereum_sepolia': '11155111'
};

function findJsonFiles(dir) {
    const files = [];
    
    function traverse(currentDir) {
        const entries = fs.readdirSync(currentDir, { withFileTypes: true });
        
        for (const entry of entries) {
            const fullPath = path.join(currentDir, entry.name);
            if (entry.isDirectory()) {
                traverse(fullPath);
            } else if (entry.name.endsWith('.json')) {
                files.push(fullPath);
            }
        }
    }
    
    traverse(dir);
    return files;
}

function getConstructorAbi(contractName) {
    try {
        // Try multiple possible paths for the contract ABI
        const possiblePaths = [
            `out/${contractName}.sol/${contractName}.json`,
            `out/authorization/${contractName}.sol/${contractName}.json`,
            `out/liquidator/${contractName}.sol/${contractName}.json`,
            `out/market-maker/${contractName}.sol/${contractName}.json`,
            `out/zaps/${contractName}.sol/${contractName}.json`,
        ];
        
        // Special case for ERC1967Proxy
        if (contractName === 'ERC1967Proxy') {
            possiblePaths.unshift('out/ERC1967Proxy.sol/ERC1967Proxy.json');
        }
        
        for (const abiPath of possiblePaths) {
            if (fs.existsSync(abiPath)) {
                const contractJson = JSON.parse(fs.readFileSync(abiPath, 'utf8'));
                const constructor = contractJson.abi.find(item => item.type === 'constructor');
                return constructor ? constructor.inputs : [];
            }
        }
        
        console.warn(`⚠️  Could not find ABI for contract ${contractName}, using basic encoding`);
        return null;
    } catch (error) {
        console.error(`Error loading ABI for ${contractName}:`, error.message);
        return null;
    }
}

function abiEncodeArguments(args, contractName) {
    if (!args || args.length === 0) {
        return '';
    }
    
    try {
        // Get constructor ABI for proper encoding
        const constructorInputs = getConstructorAbi(contractName);
        
        if (!constructorInputs || constructorInputs.length === 0) {
            // Fallback to simple concatenation (old method)
            console.warn(`⚠️  Using fallback encoding for ${contractName}`);
            let encodedArgs = args.map(arg => {
                if (typeof arg === 'string') {
                    return arg.startsWith('0x') ? arg.slice(2) : arg;
                }
                return String(arg);
            }).join('');
            return encodedArgs;
        }
        
        // Extract just the types for encoding
        const types = constructorInputs.map(input => input.type);
        
        // Convert args to proper format for ethers
        const formattedArgs = args.map((arg, index) => {
            const type = types[index];
            if (type === 'address' && typeof arg === 'string') {
                // Ensure address is properly formatted
                return arg.startsWith('0x') ? arg : `0x${arg}`;
            } else if (type === 'bytes' && typeof arg === 'string') {
                // Ensure bytes is properly formatted
                return arg.startsWith('0x') ? arg : `0x${arg}`;
            } else if (type.startsWith('uint') || type.startsWith('int')) {
                // Handle numeric types
                return String(arg);
            }
            return arg;
        });
        
        // Encode using ethers ABI coder
        const abiCoder = new AbiCoder();
        const encodedArgs = abiCoder.encode(types, formattedArgs);
        
        // Remove '0x' prefix for forge command
        return encodedArgs.startsWith('0x') ? encodedArgs.slice(2) : encodedArgs;
        
    } catch (error) {
        console.error(`❌ Error encoding arguments for ${contractName}:`, error.message);
        console.error(`   Arguments:`, args);
        
        // Fallback to simple concatenation
        console.warn(`⚠️  Using fallback encoding for ${contractName}`);
        let encodedArgs = args.map(arg => {
            if (typeof arg === 'string') {
                return arg.startsWith('0x') ? arg.slice(2) : arg;
            }
            return String(arg);
        }).join('');
        return encodedArgs;
    }
}

function getContractPath(contractName) {
    // Special case for ERC1967Proxy (external library)
    if (contractName === 'ERC1967Proxy') {
        return 'lib/size-solidity/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy';
    }
    
    // Search for the contract file recursively in src directory
    function findContractInDirectory(dir, contractName) {
        if (!fs.existsSync(dir)) return null;
        
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        
        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);
            
            if (entry.isDirectory()) {
                const found = findContractInDirectory(fullPath, contractName);
                if (found) return found;
            } else if (entry.name === `${contractName}.sol`) {
                return `${fullPath}:${contractName}`;
            }
        }
        
        return null;
    }
    
    // Try to find the contract in src directory first
    const srcPath = findContractInDirectory('src', contractName);
    if (srcPath) {
        return srcPath;
    }
    
    // Fallback to common locations if not found in src
    const possiblePaths = [
        `contracts/${contractName}.sol:${contractName}`,
        `lib/${contractName}.sol:${contractName}`,
        `src/${contractName}.sol:${contractName}` // Keep this as final fallback
    ];
    
    // Check if any of these files exist
    for (const possiblePath of possiblePaths) {
        const filePath = possiblePath.split(':')[0];
        if (fs.existsSync(filePath)) {
            return possiblePath;
        }
    }
    
    // Return src path as default if nothing found
    return `src/${contractName}.sol:${contractName}`;
}

function generateVerifyCommand(transaction, rpcUrl = DEFAULT_RPC_URL) {
    const { contractAddress, contractName, arguments: args } = transaction;
    
    if (!contractAddress || !contractName) {
        console.log(`Skipping transaction - missing contractAddress or contractName`);
        return null;
    }
    
    const contractPath = getContractPath(contractName);
    const encodedArgs = abiEncodeArguments(args, contractName);
    
    let command = `forge verify-contract ${contractAddress} ${contractPath} --compiler-version ${COMPILER_VERSION}`;
    
    if (encodedArgs) {
        command += ` --constructor-args ${encodedArgs}`;
    }
    
    command += ` --watch --rpc-url ${rpcUrl}`;
    
    return command;
}

function executeForgeCommand(command) {
    return new Promise((resolve, reject) => {
        console.log(`\n🚀 Executing: ${command}`);
        console.log('━'.repeat(80));
        
        // Parse the command to separate the executable and arguments
        const parts = command.split(' ');
        const executable = parts[0]; // 'forge'
        const args = parts.slice(1); // everything after 'forge'
        
        const process = spawn(executable, args, {
            stdio: 'pipe',
            shell: false
        });
        
        let stdout = '';
        let stderr = '';
        
        // Stream stdout to console and capture it
        process.stdout.on('data', (data) => {
            const output = data.toString();
            console.log(output.trim()); // Print to console in real-time
            stdout += output;
        });
        
        // Stream stderr to console and capture it
        process.stderr.on('data', (data) => {
            const output = data.toString();
            console.error(output.trim()); // Print to console in real-time
            stderr += output;
        });
        
        process.on('close', (code) => {
            console.log('━'.repeat(80));
            if (code === 0) {
                console.log(`✅ Command completed successfully (exit code: ${code})\n`);
                resolve({ success: true, stdout, stderr, code });
            } else {
                console.log(`❌ Command failed (exit code: ${code})\n`);
                resolve({ success: false, stdout, stderr, code });
            }
        });
        
        process.on('error', (error) => {
            console.log('━'.repeat(80));
            console.error(`❌ Error executing command: ${error.message}\n`);
            reject({ success: false, error: error.message });
        });
    });
}

async function processJsonFile(filePath, options = {}) {
    const { contractFilter, rpcUrl, execute } = options;
    
    try {
        // console.log(`\nProcessing: ${filePath}`);
        
        const content = fs.readFileSync(filePath, 'utf8');
        const data = JSON.parse(content);
        
        if (!data.transactions || !Array.isArray(data.transactions)) {
            console.log(`No transactions array found in ${filePath}`);
            return [];
        }
        
        let createTransactions = data.transactions.filter(tx => tx.transactionType === 'CREATE');
        
        // Filter by contract name if specified
        if (contractFilter) {
            createTransactions = createTransactions.filter(tx => 
                tx.contractName && tx.contractName.toLowerCase() === contractFilter.toLowerCase()
            );
        }
        
        if (createTransactions.length === 0) {
            // const filterMsg = contractFilter ? ` matching contract '${contractFilter}'` : '';
            // console.log(`No CREATE transactions${filterMsg} found in ${filePath}`);
            return [];
        }
        
        console.log(`Found ${createTransactions.length} CREATE transaction(s):`);
        const results = [];
        
        for (const [index, tx] of createTransactions.entries()) {
            console.log(`\n--- Transaction ${index + 1} ---`);
            console.log(`Contract: ${tx.contractName}`);
            console.log(`Address: ${tx.contractAddress}`);
            console.log(`Arguments: ${tx.arguments ? JSON.stringify(tx.arguments, null, 2) : 'none'}`);
            
            const command = generateVerifyCommand(tx, rpcUrl);
            if (command) {
                console.log(`\nVerify command:`);
                console.log(command);
                
                if (execute) {
                    try {
                        const result = await executeForgeCommand(command);
                        results.push({ command, result });
                    } catch (error) {
                        console.error(`Failed to execute command: ${error.message}`);
                        results.push({ command, result: { success: false, error: error.message } });
                    }
                } else {
                    console.log(''); // Empty line for readability
                    results.push({ command });
                }
            }
        }
        
        return results;
        
    } catch (error) {
        console.error(`Error processing ${filePath}:`, error.message);
        return [];
    }
}

function parseArguments() {
    const args = process.argv.slice(2);
    const options = {
        contract: null,
        network: null,
        execute: false,
        help: false
    };
    
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        
        if (arg === '--help' || arg === '-h') {
            options.help = true;
        } else if (arg === '--contract' || arg === '-c') {
            options.contract = args[++i];
        } else if (arg === '--network' || arg === '-n') {
            options.network = args[++i];
        } else if (arg === '--execute' || arg === '-e') {
            options.execute = true;
        }
    }
    
    return options;
}

function printHelp() {
    console.log(`
📋 Forge Contract Verification Script

Usage: node verify.js [options]

Options:
  --contract, -c <name>    Filter by contract name (e.g., AutoRollover, ERC1967Proxy)
  --network, -n <network>  Target network (base, mainnet, sepolia, base_sepolia)
  --execute, -e            Execute the forge commands (default: just show commands)
  --help, -h               Show this help message

Examples:
  node verify.js                              # Show all verification commands
  node verify.js --contract AutoRollover      # Show only AutoRollover commands
  node verify.js --network base               # Show contracts on base network only
  node verify.js -c ERC1967Proxy -n base      # Show ERC1967Proxy commands on base
  node verify.js -c AutoRollover -n base -e   # Execute AutoRollover verification on base

Supported networks:
  - mainnet, ethereum (chain ID 1)
  - base (chain ID 8453)
  - base_sepolia (chain ID 84532)
  - sepolia, ethereum_sepolia (chain ID 11155111)

⚠️  WARNING: Using --execute will run forge verify-contract commands that may take time
             and require valid RPC endpoints. Make sure your environment is configured.
`);
}

async function main() {
    const options = parseArguments();
    
    if (options.help) {
        printHelp();
        return;
    }
    
    console.log('🔍 Scanning for broadcast JSON files...');
    
    if (!fs.existsSync(BROADCAST_DIR)) {
        console.error(`Broadcast directory not found: ${BROADCAST_DIR}`);
        process.exit(1);
    }
    
    const jsonFiles = findJsonFiles(BROADCAST_DIR);
    
    if (jsonFiles.length === 0) {
        console.log('No JSON files found in broadcast directory');
        return;
    }
    
    console.log(`Found ${jsonFiles.length} JSON file(s)`);
    
    // Filter by network (chain ID) if specified
    let filesToProcess = jsonFiles;
    if (options.network) {
        const chainId = NETWORK_CHAIN_IDS[options.network.toLowerCase()];
        if (!chainId) {
            console.error(`Unknown network: ${options.network}`);
            console.error(`Supported networks: ${Object.keys(NETWORK_CHAIN_IDS).join(', ')}`);
            process.exit(1);
        }
        
        filesToProcess = jsonFiles.filter(file => file.includes(`/${chainId}/`));
        console.log(`Filtering to ${options.network} network (chain ID ${chainId})`);
        
        if (filesToProcess.length === 0) {
            console.log(`No files found for network ${options.network} (chain ID ${chainId})`);
            return;
        }
    }
    
    // Filter to only process run-latest.json files for cleaner output
    const latestFiles = filesToProcess.filter(file => file.includes('run-latest.json'));
    const processFiles = latestFiles.length > 0 ? latestFiles : filesToProcess;
    
    const rpcUrl = options.network || DEFAULT_RPC_URL;
    const processOptions = {
        contractFilter: options.contract,
        rpcUrl: rpcUrl,
        execute: options.execute
    };
    
    console.log(`\n📋 Processing ${processFiles.length} file(s):`);
    if (options.contract) {
        console.log(`🎯 Filtering for contract: ${options.contract}`);
    }
    if (options.network) {
        console.log(`🌐 Targeting network: ${options.network}`);
    }
    if (options.execute) {
        console.log(`⚡ Execution mode: Commands will be executed`);
    }
    
    let totalCommands = 0;
    let successfulExecutions = 0;
    let failedExecutions = 0;
    
    for (const filePath of processFiles) {
        const results = await processJsonFile(filePath, processOptions);
        totalCommands += results.length;
        
        if (options.execute) {
            results.forEach(({ result }) => {
                if (result && result.success) {
                    successfulExecutions++;
                } else if (result) {
                    failedExecutions++;
                }
            });
        }
    }
    
    console.log(`\n✅ Processing complete!`);
    if (options.execute) {
        console.log(`📊 Execution Summary:`);
        console.log(`   • Total commands: ${totalCommands}`);
        console.log(`   • Successful: ${successfulExecutions}`);
        console.log(`   • Failed: ${failedExecutions}`);
    } else {
        console.log(`Generated ${totalCommands} verification command(s).`);
        console.log('\n💡 Usage tips:');
        console.log('- Add --execute flag to run the commands automatically');
        console.log('- Copy and paste the commands above to verify your contracts manually');
        console.log('- Make sure to set the correct --rpc-url for your network');
        console.log('- Adjust contract paths if they differ from the defaults');
        console.log('- For libraries, you may need to add --libraries flags');
    }
}

if (require.main === module) {
    main();
}

module.exports = { generateVerifyCommand, abiEncodeArguments, getContractPath };