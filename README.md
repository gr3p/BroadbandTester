# Internet Speed Tester (Broadband Tester)

Very Lightweight automated broadband diagnostics: multi-server speed tests, latency checks, packet loss detection, and route tracing. All from a single PowerShell script.

## Requirements

- **Windows** with PowerShell 5.1+ or PowerShell Core 7+
- **Ookla Speedtest CLI** - downloaded automatically on first run (or manually from [speedtest.net/apps/cli](https://www.speedtest.net/apps/cli))

## Installation

1. Clone the repo or download the files
2. Run `.\BroadbandTester.ps1` - `speedtest.exe` is downloaded automatically if missing
3. Accept Ookla’s license agreement on first run

## Architecture

- `BroadbandTester.ps1` - Main script that runs speed tests against multiple servers, pings gateway/DNS, and runs traceroute
- `RunSpeedTests.ps1` - Wrapper for scheduled/repeated tests based on `script.config`
- `script.config` - Configuration file for interval and duration
- `logs/` - Auto-generated with test results

## Configuration

Edit `script.config`:

```ini
RepeatMinutes=60      # Run every 60 minutes (0 = run once)
DurationHours=24      # Run for 24 hours (0 = no limit)
Args=-PingCount 10    # Extra arguments to BroadbandTester.ps1
```

## Usage

```powershell
# Single test
.\BroadbandTester.ps1

# With fewer ping packets (faster)
.\BroadbandTester.ps1 -PingCount 5

# Scheduled tests according to config
.\RunSpeedTests.ps1
```

## Output

The test displays:
- Speed (download/upload in Mbps)
- Latency (ping, jitter)
- Packet loss
- Traceroute with hop details
- Color-coded summary with grade A–D

## License

MIT License - see [LICENSE](LICENSE)
