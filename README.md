# InternetSpeedTester

PowerShell-svit som automatiserar bredbandsmätningar med Ooklas Speedtest CLI, ping och traceroute, inklusive schemaläggning och loggning.

## Krav

- **Windows** med PowerShell 5.1+ eller PowerShell Core 7+
- **Ookla Speedtest CLI** - laddas ner automatiskt vid första körning (eller manuellt från [speedtest.net/apps/cli](https://www.speedtest.net/apps/cli))

## Installation

1. Klona repot eller ladda ner filerna
2. Kör `.\BroadbandTester.ps1` - speedtest.exe laddas ner automatiskt om den saknas
3. Acceptera Ookla's licensavtal vid första körning

## Arkitektur

- `BroadbandTester.ps1` - Huvudskriptet som kör hastighetstester mot flera servrar, pingar gateway/DNS, och kör traceroute
- `RunSpeedTests.ps1` - Wrapper för schemalagda/upprepade tester baserat på `script.config`
- `script.config` - Konfigurationsfil för intervall och varaktighet
- `logs/` - Genereras automatiskt med testresultat

## Konfiguration

Redigera `script.config`:

```ini
RepeatMinutes=60      # Kör var 60:e minut (0 = kör en gång)
DurationHours=24      # Kör i 24 timmar (0 = ingen gräns)
Args=-PingCount 10    # Extra argument till BroadbandTester.ps1
```

## Användning

```powershell
# Enstaka test
.\BroadbandTester.ps1

# Med färre ping-paket (snabbare)
.\BroadbandTester.ps1 -PingCount 5

# Schemalagda tester enligt config
.\RunSpeedTests.ps1
```

## Output

Testet visar:
- Hastighet (download/upload i Mbps)
- Latens (ping, jitter)
- Paketförlust
- Traceroute med hop-detaljer
- Färgkodad sammanfattning med betyg A-D

## Licens

MIT License - se [LICENSE](LICENSE)
