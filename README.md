# gatk.FilterMutectCalls (v1)

**Description**: Filters somatic SNVs and indels called by Mutect2. Applies hard filters and a probabilistic model to the raw Mutect2 variant calls to distinguish true somatic mutations from sequencing artifacts and germline variants.

**Authors**: Broad Institute of MIT and Harvard; GenePattern Team, UC San Diego

**Contact**: [GenePattern Community Forum](https://groups.google.com/g/genepattern-help)

**Algorithm Version**: GATK 4.1.4.1 FilterMutectCalls

## Summary

**gatk.FilterMutectCalls** is the final filtering step in the GATK4 Best Practices somatic variant calling pipeline. It takes the raw, unfiltered VCF produced by Mutect2 and applies a multi-pass filtering strategy that combines:

- **Hard filters**: Remove calls with too many reads from the opposite strand, too few supporting reads, or other quality issues
- **Probabilistic model**: Uses per-variant statistics, cross-sample contamination estimates, read orientation bias priors, and tumor segmentation to compute a posterior probability that each call is a true somatic mutation
- **Threshold optimization**: Applies an optimal threshold (by default maximizing F-score) to convert posterior probabilities into PASS/FILTER decisions

Each variant in the output VCF is annotated with a FILTER field: `PASS` for calls that pass all filters, or one or more filter codes (e.g., `contamination`, `orientation`, `weak_evidence`) for filtered calls.

**Typical pipeline position:**

```
Mutect2 (unfiltered VCF + stats)
         |
         +---> LearnReadOrientationModel  ---> artifact_priors.tar.gz
         |
         +---> GetPileupSummaries  ---> pileup.table
                   |
                   v
              CalculateContamination  ---> contamination.table
                                           segments.table
                                                |
                                                v
                                      gatk.FilterMutectCalls
                                                |
                                                v
                                       filtered_variants.vcf.gz
```

While all auxiliary inputs (stats, contamination table, tumor segmentation, orientation priors) are optional, providing them substantially improves filtering accuracy. Running FilterMutectCalls without these files will produce a filtered VCF based on hard filters only.

**Important notes on input staging:** Because GenePattern's input staging directory may be read-only on the server, the wrapper script copies the input VCF, its optional .tbi index, the reference FASTA, and its optional .fai index into the writable job working directory before invoking GATK. After the job completes (successfully or with an error), all locally staged copies are automatically removed.

## References

1. Van der Auwera, G.A. & O'Connor, B.D. (2020). *Genomics in the Cloud: Using Docker, GATK, and WDL in Terra*. O'Reilly Media.
2. McKenna, A. et al. (2010). The Genome Analysis Toolkit: A MapReduce framework for analyzing next-generation DNA sequencing data. *Genome Research*, 20(9):1297-1303. https://doi.org/10.1101/gr.107524.110
3. GATK FilterMutectCalls tool documentation: https://gatk.broadinstitute.org/hc/en-us/articles/360036856831-FilterMutectCalls
4. GATK Somatic short variant discovery best practices: https://gatk.broadinstitute.org/hc/en-us/articles/360035894731

## Source Links

* [GenePattern gatk.FilterMutectCalls source repository](https://github.com/genepattern/gatk.FilterMutectCalls)
* [GATK Official Docker image: broadinstitute/gatk:4.1.4.1](https://hub.docker.com/r/broadinstitute/gatk)
* [GATK Source Repository](https://github.com/broadinstitute/gatk)

## Parameters

| Name | Description | Default Value |
| :--- | :--- | :--- |
| input vcf \* | Unfiltered VCF produced by Mutect2 (.vcf or .vcf.gz) | -- |
| input vcf tbi | Tabix index (.tbi) for a bgzipped input VCF; required if input VCF is .vcf.gz | -- |
| reference \* | Reference genome FASTA file matching the genome build used by Mutect2 | -- |
| reference fai | FASTA index (.fai) for the reference genome | -- |
| output vcf name \* | Name for the output filtered VCF file | filtered_variants.vcf.gz |
| stats file | Mutect2 stats file (output of Mutect2, typically named *.vcf.gz.stats) | -- |
| contamination table | Contamination table from CalculateContamination | -- |
| tumor segmentation | Tumor segments table from CalculateContamination (--tumor-segmentation output) | -- |
| orientation bias artifact priors | Read orientation model .tar.gz from LearnReadOrientationModel | -- |
| arguments file | GATK arguments file for additional FilterMutectCalls parameters | -- |
| gatk config file | GATK configuration file (.properties format) | -- |

\* required

## Input Files

1. **input vcf** *(required)*
   The unfiltered VCF file produced by Mutect2. This is the primary input, containing all raw somatic variant candidates before filtering. The file may be either an uncompressed VCF (.vcf) or a bgzipped VCF (.vcf.gz). If bgzipped, a corresponding tabix index (.tbi) must also be provided via the **input vcf tbi** parameter.
   - **Format**: VCF (.vcf) or bgzipped VCF (.vcf.gz)
   - **Requirements**: Must be the direct output of Mutect2; genome build must match the reference genome

2. **input vcf tbi** *(optional)*
   The tabix index file (.tbi) corresponding to a bgzipped input VCF. GATK requires the index to reside in the same directory as the VCF, with the name `<vcf>.tbi`. The wrapper handles this staging automatically.
   - **Format**: Tabix index (.vcf.gz.tbi)
   - **Requirements**: Must correspond to the bgzipped input VCF; omit this parameter if the input VCF is uncompressed

3. **reference** *(required)*
   The reference genome FASTA file. Must be the same genome build used when running Mutect2. GATK also requires:
   - A `.fai` index (provide via **reference fai**)
   - A `.dict` sequence dictionary -- GATK looks for this automatically in the same directory as the FASTA. If you need to provide it explicitly, use the **arguments file** to pass `--sequence-dictionary /path/to/ref.dict`.
   - **Format**: FASTA (.fa, .fasta, .fna)
   - **Note**: Large reference files (typically 3+ GB for human genomes) are copied into the job working directory by the wrapper.

4. **reference fai** *(optional)*
   The FASTA index file (.fai) for the reference genome, generated by `samtools faidx`. The wrapper stages both the reference and this index into the same directory so GATK can locate the index alongside the FASTA.
   - **Format**: FASTA index (.fai)

5. **stats file** *(optional)*
   The stats file produced by Mutect2 alongside the unfiltered VCF (typically named `<output>.vcf.gz.stats`). Contains per-read-group and per-orientation statistics that the filtering model uses to set priors. If not provided, GATK will attempt to locate it automatically using the input VCF name; providing it explicitly is recommended to avoid path resolution issues in GenePattern.
   - **Format**: Tab-separated stats file (.stats or .txt)
   - **Recommendation**: Always provide this file when it is available

6. **contamination table** *(optional)*
   The contamination table produced by CalculateContamination. Contains per-sample cross-sample contamination fraction estimates. Providing this enables FilterMutectCalls to down-weight or filter variants that are likely due to contamination from another sample.
   - **Format**: Tab-separated table (.table or .txt)

7. **tumor segmentation** *(optional)*
   The tumor segmentation table produced by CalculateContamination via its `--tumor-segmentation` output. Contains minor allele fraction estimates for each genomic segment. This information helps FilterMutectCalls distinguish somatic variants from LOH regions and germline contamination.
   - **Format**: Tab-separated table (.table or .txt)

8. **orientation bias artifact priors** *(optional)*
   A .tar.gz archive of read orientation model parameters produced by LearnReadOrientationModel. This model captures the rate of orientation-dependent sequencing artifacts (e.g., OxoG C>A transversions) at each trinucleotide context. Providing this file enables filtering of orientation bias artifacts.
   - **Format**: Compressed tar archive (.tar.gz)

9. **arguments file** *(optional)*
   A plain-text file containing additional GATK command-line arguments, one per line or as `argument=value` pairs. Use this to specify advanced FilterMutectCalls options not exposed as dedicated module parameters. Passed to GATK via `--arguments_file`.
   - **Format**: Plain text (.txt)
   - **Example contents**:
     ```
     --contamination-estimate
     0.02
     --threshold-strategy
     OPTIMAL_F_SCORE
     --min-allele-fraction
     0.05
     --mitochondria-mode
     --java-options
     -Xmx6g
     ```

10. **gatk config file** *(optional)*
    A GATK configuration file in Java properties format. Allows customization of GATK runtime behavior such as logging verbosity, performance tuning, and default argument values. Passed to GATK via `--gatk-config-file`.
    - **Format**: Properties file (.properties, .conf, .config, or .txt)

## Output Files

1. **Filtered VCF** (filename specified by **output vcf name**, default: `filtered_variants.vcf.gz`)
   A VCF file containing all variant sites from the input, with FILTER field annotations indicating which calls passed filtering. Variants with `PASS` in the FILTER field are high-confidence somatic calls.

   Common filter codes applied by FilterMutectCalls:

   | Filter Code | Description |
   | :--- | :--- |
   | `PASS` | Variant passes all filters |
   | `weak_evidence` | Posterior probability of being a somatic variant is below the threshold |
   | `contamination` | Allele fraction is consistent with contamination |
   | `orientation` | Evidence of read orientation artifact |
   | `strand_bias` | Evidence of strand bias artifact |
   | `slippage` | Evidence of polymerase slippage in a short tandem repeat |
   | `normal_artifact` | Evidence of artifact in the matched normal sample |
   | `germline` | Evidence that the variant is a germline event |
   | `multiallelic` | Site has more than one alt allele |
   | `fragment` | Fragment (insert size) length filter |
   | `base_qual` | Median base quality of alt reads is below threshold |
   | `map_qual` | Median mapping quality of alt reads is below threshold |
   | `position` | Median distance of alt reads from the end of the read is below threshold |
   | `n_ratio` | Ratio of N bases in the pileup is above threshold |
   | `low_allele_frac` | Allele fraction is below the minimum threshold |

2. **Filtering statistics** (`<output_vcf_name>.filteringStats.tsv`)
   A tab-separated file summarizing the filtering thresholds chosen and the number of variants assigned to each filter. Produced automatically by GATK alongside the filtered VCF.

## Example Data

Input:
- Unfiltered Mutect2 VCF: Available from [GATK Somatic Short Variant Discovery Tutorial](https://gatk.broadinstitute.org/hc/en-us/articles/360035531132)
- Reference genome (hg38): Available from [GATK Resource Bundle](https://gatk.broadinstitute.org/hc/en-us/articles/360035890811-Resource-bundle)

## Requirements

- **Docker image**: `broadinstitute/gatk:4.1.4.1`
- **Runtime environment**: GenePattern server with Docker support
- **Memory**: Minimum 4 GB RAM; 8 GB or more recommended. Java heap size can be adjusted via `--java-options -Xmx<N>g` in the **arguments file**.
- **Disk space**: Sufficient to stage the input VCF and reference FASTA in the job working directory. Human reference genomes are typically 3+ GB.
- **Input format requirements**:
  - Input VCF must be the direct output of Mutect2
  - Reference genome must match the build used for Mutect2 and must have a .fai index and .dict dictionary accessible in the same directory
  - All genome builds must be consistent across all input files
- **Staging note**: The wrapper automatically copies the input VCF (and optional .tbi), reference FASTA (and optional .fai) into the writable job working directory before invoking GATK, and removes them upon job completion.

## License

The GATK tool is licensed under the [BSD 3-Clause License](https://github.com/broadinstitute/gatk/blob/master/LICENSE.TXT) by the Broad Institute of MIT and Harvard. The GenePattern module wrapper is made available under the [MIT License](https://opensource.org/licenses/MIT). Use of GATK for commercial purposes may require a separate license; see the [Broad Institute GATK licensing page](https://gatk.broadinstitute.org/hc/en-us/articles/360057165250) for details.

## Version Comments

| Version | Release Date | Description |
| :--- | :--- | :--- |
| 1 | 2026-03-30 | Initial release of the gatk.FilterMutectCalls GenePattern module wrapping GATK 4.1.4.1 FilterMutectCalls. Exposes required inputs (input VCF + optional index, reference + optional index, output name) and optional filtering inputs (stats file, contamination table, tumor segmentation, orientation bias priors), plus arguments file and GATK config file for advanced options. Wrapper stages indexed input files into the writable job working directory and performs automatic cleanup on exit. |
