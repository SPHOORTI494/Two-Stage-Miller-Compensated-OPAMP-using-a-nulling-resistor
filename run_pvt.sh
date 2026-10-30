#!/bin/bash

# ==========================================================
# AUTOMATED PVT ANALYSIS
# Two-Stage Miller Compensated CMOS Op-Amp
# Testbench: opamp/opamp_dc_test_for_pm
# ==========================================================

PROJECT="/Design/INTERNS/Sphoorti/Desktop/TSMC_180BCD"
PVT_DIR="$PROJECT/ocean/pvt_results"
TEMPLATE="$PVT_DIR/test_ss.ocn"

CSV="$PVT_DIR/PVT_summary.csv"
GENERATED="$PVT_DIR/generated_ocn"
LOGS="$PVT_DIR/logs"

mkdir -p "$GENERATED" "$LOGS"

# PVT conditions
CORNERS=(tt ss ff sf fs)
VOLTAGES=(1.62 1.80 1.98)
TEMPERATURES=(-40 27 125)

# CSV header
echo "Process,VDD_V,Temperature_C,Gain_dB,UGB_MHz,Phase_Margin_deg,Gain_Status,PM_Status,Overall_Status" > "$CSV"

# Run from project root so cds.lib resolves correctly
cd "$PROJECT" || exit 1

TOTAL=0
SUCCESS=0
FAILED=0

for corner in "${CORNERS[@]}"; do

    for vdd in "${VOLTAGES[@]}"; do

        for temperature in "${TEMPERATURES[@]}"; do

            TOTAL=$((TOTAL + 1))

            CORNER="${corner^^}"
            NAME="${corner}_${vdd}V_${temperature}C"

            OCN_FILE="$GENERATED/${NAME}.ocn"
            LOG_FILE="$LOGS/${NAME}.log"
            RESULT_DIR="$PVT_DIR/results_${NAME}"

            mkdir -p "$RESULT_DIR"

            echo
            echo "=================================================="
            echo "Running $TOTAL / 45 : $NAME"
            echo "=================================================="

            # Generate an OCEAN script from the validated template
            sed \
                -e "s/\"ss_lib\"/\"${corner}_lib\"/" \
                -e "s/desVar(\"VDD\" 1.8)/desVar(\"VDD\" ${vdd})/" \
                -e "s/temp(27)/temp(${temperature})/" \
                -e "s|resultsDir(\".*\")|resultsDir(\"${RESULT_DIR}\")|" \
                -e 's/TT BASELINE RESULTS/PVT RESULTS/' \
                -e '/phaseAtUGB =/a\
printf("PVT_METRICS,%g,%g,%g\\n" gain ugb phaseAtUGB)' \
                "$TEMPLATE" > "$OCN_FILE"

            # Run OCEAN
            ocean -restore "$OCN_FILE" > "$LOG_FILE" 2>&1

            # Extract metrics
            METRICS=$(grep 'PVT_METRICS' "$LOG_FILE" | tail -n 1 | sed 's/.*PVT_METRICS,//')

            if [ -z "$METRICS" ]; then

                echo "$CORNER,$vdd,$temperature,NA,NA,NA,ERROR,ERROR,ERROR" >> "$CSV"

                echo "ERROR: Simulation failed. Check $LOG_FILE"
                FAILED=$((FAILED + 1))
                continue

            fi

            IFS=',' read -r GAIN UGB PM <<< "$METRICS"

            # Convert UGB from Hz to MHz and determine PASS/FAIL
            read -r UGB_MHZ GAIN_STATUS PM_STATUS OVERALL_STATUS <<< "$(
                awk -v gain="$GAIN" -v ugb="$UGB" -v pm="$PM" '
                BEGIN {
                    ugb_mhz = ugb / 1000000

                    gain_status = (gain >= 60) ? "PASS" : "FAIL"
                    pm_status = (pm >= 50) ? "PASS" : "FAIL"
                    overall = (gain >= 60 && pm >= 50) ? "PASS" : "FAIL"

                    printf "%.6f %s %s %s\n",
                           ugb_mhz, gain_status, pm_status, overall
                }'
            )"

            # Write CSV row
            echo "$CORNER,$vdd,$temperature,$GAIN,$UGB_MHZ,$PM,$GAIN_STATUS,$PM_STATUS,$OVERALL_STATUS" >> "$CSV"

            echo "Gain       : $GAIN dB ($GAIN_STATUS)"
            echo "UGB        : $UGB_MHZ MHz"
            echo "Phase Margin: $PM degrees ($PM_STATUS)"
            echo "Overall    : $OVERALL_STATUS"

            SUCCESS=$((SUCCESS + 1))

        done
    done
done

echo
echo "=================================================="
echo "PVT AUTOMATION COMPLETED"
echo "=================================================="
echo "Total combinations : $TOTAL"
echo "Successful runs    : $SUCCESS"
echo "Failed runs        : $FAILED"
echo
echo "CSV report:"
echo "$CSV"
echo "=================================================="
