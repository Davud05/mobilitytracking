#!/usr/bin/env bash
# Generate the EF Core migration for tickets.product_code -> tickets.product_id.
# Runs inside mcr.microsoft.com/dotnet/sdk:8.0 with this folder mounted at /work.
set -euo pipefail

cd /work
dotnet tool install --tool-path /tmp/tools dotnet-ef --version 8.0.10 > /dev/null
export PATH="$PATH:/tmp/tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

rm -rf Migrations out Model.cs
mkdir out

cp stages/Before.cs.txt Model.cs
dotnet ef migrations add InitialTickets

cp stages/After.cs.txt Model.cs
dotnet ef migrations add TicketProductId

dotnet ef migrations script InitialTickets TicketProductId --idempotent --output out/ticket_product_id.sql
cp Migrations/*_TicketProductId.cs out/TicketProductId.cs
rm -f Model.cs
