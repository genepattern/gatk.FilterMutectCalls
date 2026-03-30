#!/bin/bash
set -euo pipefail

# gatk.FilterMutectCalls GenePattern wrapper
# Filters somatic SNVs and indels called by Mutect2.
#
# Required GATK arguments used: -V (input VCF), -R (reference), -O (output)
# Optional GATK arguments used: --stats, --contamination-table,
#   --tumor-segmentation, --orientation-bias-artifact-priors,
#   --arguments_file, --gatk-config-file
#
# The wrapper stages VCF + optional .tbi index, and reference + optional .fai
# index into the writable job working directory before invoking GATK, since
# GenePattern input staging directories may be read-only.

TOOL_NAME="gatk.FilterMutectCalls"

# ---------------------------------------------------------------------------
# Parameter variables (populated by parse_arguments)
# ---------------------------------------------------------------------------
INPUT_VCF=""
INPUT_VCF_TBI=""
REFERENCE=""
REFERENCE_FAI=""
REFERENCE_DICT=""
OUTPUT_VCF_NAME=""
STATS_FILE=""
CONTAMINATION_TABLE=""
TUMOR_SEGMENTATION=""
ORIENTATION_BIAS_ARTIFACT_PRIORS=""
ARGUMENTS_FILE=""
GATK_CONFIG_FILE=""

# ---------------------------------------------------------------------------
# Staged (local working-directory) copies -- tracked for cleanup
# ---------------------------------------------------------------------------
LOCAL_VCF=""
LOCAL_VCF_TBI=""
LOCAL_REFERENCE=""
LOCAL_REFERENCE_FAI=""
LOCAL_REFERENCE_DICT=""

# ---------------------------------------------------------------------------
# Cleanup trap -- always runs on EXIT (success or failure)
# ---------------------------------------------------------------------------
cleanup() {
    echo "[INFO] Cleaning up staged input files from working directory..."
    [[ -n "$LOCAL_VCF"           && -f "$LOCAL_VCF"           ]] && rm -f "$LOCAL_VCF"           && echo "[INFO] Removed $LOCAL_VCF"
    [[ -n "$LOCAL_VCF_TBI"       && -f "$LOCAL_VCF_TBI"       ]] && rm -f "$LOCAL_VCF_TBI"       && echo "[INFO] Removed $LOCAL_VCF_TBI"
    [[ -n "$LOCAL_REFERENCE"      && -f "$LOCAL_REFERENCE"      ]] && rm -f "$LOCAL_REFERENCE"      && echo "[INFO] Removed $LOCAL_REFERENCE"
    [[ -n "$LOCAL_REFERENCE_FAI"  && -f "$LOCAL_REFERENCE_FAI"  ]] && rm -f "$LOCAL_REFERENCE_FAI"  && echo "[INFO] Removed $LOCAL_REFERENCE_FAI"
    [[ -n "$LOCAL_REFERENCE_DICT" && -f "$LOCAL_REFERENCE_DICT" ]] && rm -f "$LOCAL_REFERENCE_DICT" && echo "[INFO] Removed $LOCAL_REFERENCE_DICT"
    echo "[INFO] Cleanup complete."
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "GenePattern wrapper for GATK FilterMutectCalls"
    echo ""
    echo "Required options:"
    echo "  --input.vcf FILE                   Unfiltered Mutect2 VCF"
    echo "  --reference FILE                   Reference genome FASTA"
    echo "  --output.vcf.name TEXT             Name for the output filtered VCF"
    echo ""
    echo "Optional options:"
    echo "  --input.vcf.tbi FILE               Tabix index (.tbi) for input VCF"
    echo "  --reference.fai FILE               FASTA index (.fai) for reference"
    echo "  --reference.dict FILE              Sequence dictionary (.dict) for reference"
    echo "  --stats.file FILE                  Mutect2 stats file"
    echo "  --contamination.table FILE         CalculateContamination output table"
    echo "  --tumor.segmentation FILE          CalculateContamination segments table"
    echo "  --orientation.bias.artifact.priors FILE  LearnReadOrientationModel .tar.gz"
    echo "  --arguments.file FILE              GATK arguments file"
    echo "  --gatk.config.file FILE            GATK configuration file"
    echo "  -h, --help                         Show this help and exit"
    exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        echo "[ERROR] No arguments provided."
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input.vcf)
                INPUT_VCF="$2"
                shift 2
                ;;
            --input.vcf.tbi)
                INPUT_VCF_TBI="$2"
                shift 2
                ;;
            --reference)
                REFERENCE="$2"
                shift 2
                ;;
            --reference.fai)
                REFERENCE_FAI="$2"
                shift 2
                ;;
            --reference.dict)
                REFERENCE_DICT="$2"
                shift 2
                ;;
            --output.vcf.name)
                OUTPUT_VCF_NAME="$2"
                shift 2
                ;;
            --stats.file)
                STATS_FILE="$2"
                shift 2
                ;;
            --contamination.table)
                CONTAMINATION_TABLE="$2"
                shift 2
                ;;
            --tumor.segmentation)
                TUMOR_SEGMENTATION="$2"
                shift 2
                ;;
            --orientation.bias.artifact.priors)
                ORIENTATION_BIAS_ARTIFACT_PRIORS="$2"
                shift 2
                ;;
            --arguments.file)
                ARGUMENTS_FILE="$2"
                shift 2
                ;;
            --gatk.config.file)
                GATK_CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "[ERROR] Unknown option: $1"
                usage
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
validate_inputs() {
    local errors=0

    # Required parameter presence checks
    if [[ -z "$INPUT_VCF" ]];       then echo "[ERROR] --input.vcf is required";       errors=$((errors+1)); fi
    if [[ -z "$REFERENCE" ]];       then echo "[ERROR] --reference is required";        errors=$((errors+1)); fi
    if [[ -z "$OUTPUT_VCF_NAME" ]]; then echo "[ERROR] --output.vcf.name is required";  errors=$((errors+1)); fi

    # File existence checks (only when the variable is set)
    if [[ -n "$INPUT_VCF"                      && ! -f "$INPUT_VCF"                      ]]; then echo "[ERROR] Input VCF not found: $INPUT_VCF";                                    errors=$((errors+1)); fi
    if [[ -n "$INPUT_VCF_TBI"                  && ! -f "$INPUT_VCF_TBI"                  ]]; then echo "[ERROR] Input VCF index not found: $INPUT_VCF_TBI";                          errors=$((errors+1)); fi
    if [[ -n "$REFERENCE"                      && ! -f "$REFERENCE"                      ]]; then echo "[ERROR] Reference FASTA not found: $REFERENCE";                              errors=$((errors+1)); fi
    if [[ -n "$REFERENCE_FAI"                  && ! -f "$REFERENCE_FAI"                  ]]; then echo "[ERROR] Reference FAI index not found: $REFERENCE_FAI";                      errors=$((errors+1)); fi
    if [[ -n "$REFERENCE_DICT"                 && ! -f "$REFERENCE_DICT"                 ]]; then echo "[ERROR] Reference dict not found: $REFERENCE_DICT";                            errors=$((errors+1)); fi
    if [[ -n "$STATS_FILE"                     && ! -f "$STATS_FILE"                     ]]; then echo "[ERROR] Stats file not found: $STATS_FILE";                                  errors=$((errors+1)); fi
    if [[ -n "$CONTAMINATION_TABLE"            && ! -f "$CONTAMINATION_TABLE"            ]]; then echo "[ERROR] Contamination table not found: $CONTAMINATION_TABLE";                errors=$((errors+1)); fi
    if [[ -n "$TUMOR_SEGMENTATION"             && ! -f "$TUMOR_SEGMENTATION"             ]]; then echo "[ERROR] Tumor segmentation file not found: $TUMOR_SEGMENTATION";             errors=$((errors+1)); fi
    if [[ -n "$ORIENTATION_BIAS_ARTIFACT_PRIORS" && ! -f "$ORIENTATION_BIAS_ARTIFACT_PRIORS" ]]; then echo "[ERROR] Orientation bias priors not found: $ORIENTATION_BIAS_ARTIFACT_PRIORS"; errors=$((errors+1)); fi
    if [[ -n "$ARGUMENTS_FILE"                 && ! -f "$ARGUMENTS_FILE"                 ]]; then echo "[ERROR] Arguments file not found: $ARGUMENTS_FILE";                          errors=$((errors+1)); fi
    if [[ -n "$GATK_CONFIG_FILE"               && ! -f "$GATK_CONFIG_FILE"               ]]; then echo "[ERROR] GATK config file not found: $GATK_CONFIG_FILE";                      errors=$((errors+1)); fi

    if [[ "$errors" -gt 0 ]]; then
        echo "[ERROR] $errors validation error(s) found. Exiting."
        exit 1
    fi

    echo "[INFO] Input validation passed."
}

# ---------------------------------------------------------------------------
# Stage inputs into the writable job working directory
#
# GATK requires the index file to sit alongside the data file and share the
# same base name, e.g.:
#   variants.vcf.gz  +  variants.vcf.gz.tbi
#   ref.fasta        +  ref.fasta.fai
#
# The GenePattern staging directory may be read-only, so we copy the VCF
# (and optionally its .tbi index) and the reference (and optionally its .fai
# index) into the current working directory (the writable job directory).
# ---------------------------------------------------------------------------
stage_inputs() {
    local workdir
    workdir="$(pwd)"
    echo "[INFO] Staging input files into job working directory: $workdir"

    # -- Input VCF ------------------------------------------------------------
    LOCAL_VCF="${workdir}/$(basename "${INPUT_VCF}")"
    echo "[INFO] Copying VCF: ${INPUT_VCF} -> ${LOCAL_VCF}"
    cp "${INPUT_VCF}" "${LOCAL_VCF}"

    # TBI index must be named <vcf>.tbi (GATK auto-discovers <input>.tbi)
    if [[ -n "$INPUT_VCF_TBI" ]]; then
        LOCAL_VCF_TBI="${LOCAL_VCF}.tbi"
        echo "[INFO] Copying VCF index: ${INPUT_VCF_TBI} -> ${LOCAL_VCF_TBI}"
        cp "${INPUT_VCF_TBI}" "${LOCAL_VCF_TBI}"
    fi

    # -- Reference FASTA ------------------------------------------------------
    LOCAL_REFERENCE="${workdir}/$(basename "${REFERENCE}")"
    echo "[INFO] Copying reference: ${REFERENCE} -> ${LOCAL_REFERENCE}"
    cp "${REFERENCE}" "${LOCAL_REFERENCE}"

    # FAI index must be named <reference>.fai
    if [[ -n "$REFERENCE_FAI" ]]; then
        LOCAL_REFERENCE_FAI="${LOCAL_REFERENCE}.fai"
        echo "[INFO] Copying reference index: ${REFERENCE_FAI} -> ${LOCAL_REFERENCE_FAI}"
        cp "${REFERENCE_FAI}" "${LOCAL_REFERENCE_FAI}"
    fi

    # Sequence dictionary must be named <reference_without_extension>.dict
    # GATK auto-discovers ref.dict (or ref.fasta.dict) in the same directory as the FASTA
    if [[ -n "$REFERENCE_DICT" ]]; then
        local ref_no_ext
        ref_no_ext="${LOCAL_REFERENCE%.*}"
        LOCAL_REFERENCE_DICT="${ref_no_ext}.dict"
        echo "[INFO] Copying reference dict: ${REFERENCE_DICT} -> ${LOCAL_REFERENCE_DICT}"
        cp "${REFERENCE_DICT}" "${LOCAL_REFERENCE_DICT}"
    fi

    echo "[INFO] Staging complete."
}

# ---------------------------------------------------------------------------
# Execute GATK FilterMutectCalls
# ---------------------------------------------------------------------------
run_tool() {
    # Build the command array with required GATK arguments:
    #   -V  input VCF from Mutect2
    #   -R  reference FASTA
    #   -O  output filtered VCF
    local -a cmd=(
        gatk FilterMutectCalls
        -V "${LOCAL_VCF}"
        -R "${LOCAL_REFERENCE}"
        -O "${OUTPUT_VCF_NAME}"
    )

    # Append optional arguments when provided
    if [[ -n "$STATS_FILE" ]]; then
        cmd+=(--stats "${STATS_FILE}")
    fi

    if [[ -n "$CONTAMINATION_TABLE" ]]; then
        cmd+=(--contamination-table "${CONTAMINATION_TABLE}")
    fi

    if [[ -n "$TUMOR_SEGMENTATION" ]]; then
        cmd+=(--tumor-segmentation "${TUMOR_SEGMENTATION}")
    fi

    if [[ -n "$ORIENTATION_BIAS_ARTIFACT_PRIORS" ]]; then
        cmd+=(--orientation-bias-artifact-priors "${ORIENTATION_BIAS_ARTIFACT_PRIORS}")
    fi

    if [[ -n "$ARGUMENTS_FILE" ]]; then
        cmd+=(--arguments_file "${ARGUMENTS_FILE}")
    fi

    if [[ -n "$GATK_CONFIG_FILE" ]]; then
        cmd+=(--gatk-config-file "${GATK_CONFIG_FILE}")
    fi

    echo "[INFO] Executing: ${cmd[*]}"
    echo "-------------------------------------------------------------------"

    "${cmd[@]}"
    local exit_code=$?

    echo "-------------------------------------------------------------------"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "[ERROR] gatk FilterMutectCalls failed with exit code ${exit_code}."
        exit "${exit_code}"
    fi

    echo "[INFO] gatk FilterMutectCalls completed successfully."
    echo "[INFO] Output written to: ${OUTPUT_VCF_NAME}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "[INFO] === ${TOOL_NAME} wrapper starting ==="
    echo "[INFO] Working directory: $(pwd)"

    parse_arguments "$@"
    validate_inputs
    stage_inputs
    run_tool

    echo "[INFO] === ${TOOL_NAME} wrapper finished successfully ==="
}

main "$@"
