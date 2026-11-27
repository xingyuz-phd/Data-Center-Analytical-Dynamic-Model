# DC-RMS: Data Center Computing Load RMS & EMT Models

Open-source **MATLAB RMS** and **PSCAD/EMTDC EMT** models of UPS-fed AI data center computing loads for power system stability and oscillation studies, developed at the **Thayer School of Engineering, Dartmouth College**.

Accompanying paper:
> **Dynamic Modeling of Data Center Computing Loads for Power System Studies: From EMT to RMS**  
> Xingyu Zhao, Junbo Zhao, and Yingyi Tang — Thayer School of Engineering, Dartmouth College

## Repository Structure

```text
DC-RMS/
├── README.md
├── docs/figures/                           # PNG result figures rendered below
├── EMT/                                    # PSCAD/EMTDC benchmark models
│   ├── DC_EMT_lib.pslx
│   ├── DC_EMT_ws.pswx
│   ├── DC_EMT_normal.pscx                  # Normal-mode VRT & square-wave load
│   ├── DC_EMT_bypass.pscx                  # Normal <-> Bypass mode switching
│   └── DC_EMT_normal_oscillation.pscx      # 6 Hz small-signal amplification
└── RMS/                                    # MATLAB RMS scripts, data & vector PDFs
    ├── DC_RMS_Normal.m                     # Fig. 1 & Fig. 2
    ├── DC_RMS_Bypass.m                     # Fig. 3
    ├── DC_RMS_Modal_Normal.m               # Fig. 4 & Fig. 5
    ├── DC_RMS_Modal_Bypass.m               # Fig. 6 & Fig. 7
    ├── DC_RMS_Oscillation_Normal.m         # Fig. 8
    ├── Normal_EMT_PerUnit_Data.xlsx
    ├── Bypass_EMT_PerUnit_Data.xlsx
    ├── Normal_Oscillation_EMT_PerUnit_Data.xlsx
    └── Fig1_*.pdf ... Fig8_*.pdf
```

## RMS vs. EMT Benchmark Results

### 1. Grid Voltage Sag & VRT Backup (`DC_RMS_Normal.m`)

RMS tracks EMT closely across the voltage sag ($`0.45 \mathrm{p.u.}`$), battery backup transfer, and soft recovery, while $`\mathrm{v}_{\mathrm{pfc}}^{\mathrm{av}} \pm \Delta\mathrm{v}_{\mathrm{pfc}}`$ bounds the three-phase $`2\omega`$ ripple.

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig1_VRT_1_to_5s.png&quot; width=&quot;72%&quot; alt=&quot;VRT Benchmark&quot;&gt;
&lt;/p&gt;

### 2. Computing Load Fluctuation Propagation (`DC_RMS_Normal.m`)

Under a periodic square-wave chip demand ($`0.18-0.78 \mathrm{p.u.}`$, 0.5 Hz, 70% duty cycle), the RMS model accurately captures upstream disturbance propagation to the grid.

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig2_LoadProp_5_to_10s.png&quot; width=&quot;72%&quot; alt=&quot;Load Propagation Benchmark&quot;&gt;
&lt;/p&gt;

### 3. Normal ↔ Bypass Mode Switching (`DC_RMS_Bypass.m`)

At $`\mathrm{p}_{\mathrm{chip},3\phi}=0.7 \mathrm{p.u.}`$, RMS reproduces both the Normal-to-Bypass ($`t=0.5 \mathrm{s}`$) and Bypass-to-Normal ($`t=1.5 \mathrm{s}`$) transients in $`\mathrm{p}_g`$, $`\mathrm{v}_{\mathrm{dc}}`$, and $`\mathrm{v}_{\mathrm{pfc}}`$.

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig3_Bypass_2_to_5s.png&quot; width=&quot;72%&quot; alt=&quot;Bypass Switching Benchmark&quot;&gt;
&lt;/p&gt;

## Modal & Power-Swing Amplification Analysis

### Normal Mode (`DC_RMS_Modal_Normal.m`)

Double-conversion UPS isolates the PSUs from $`\mathrm{X}_g`$; grid coupling gain rises abruptly only near the static voltage-stability limit, while reducing $`f_{\mathrm{bw,vsi}}`$ destabilizes the internal VSI–PSU loop (Hopf crossing near 21.5 Hz).

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig4_Modal_RootLocus.png&quot; width=&quot;90%&quot; alt=&quot;Normal Mode Root Locus&quot;&gt;
&lt;/p&gt;

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig5_Gain_FreqResp.png&quot; width=&quot;90%&quot; alt=&quot;Normal Mode Gain Frequency Response&quot;&gt;
&lt;/p&gt;

### Bypass Mode (`DC_RMS_Modal_Bypass.m`)

With the VSI disconnected, PSUs couple directly to the grid, causing sharper low-frequency grid-coupling peaks ($`3.11\times`$ near 1.5 Hz at $`\mathrm{X}_g=0.63 \mathrm{p.u.}`$) near the voltage-stability limit.

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig6_Bypass_RootLocus.png&quot; width=&quot;90%&quot; alt=&quot;Bypass Mode Root Locus&quot;&gt;
&lt;/p&gt;

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig7_Bypass_Gain_FreqResp.png&quot; width=&quot;90%&quot; alt=&quot;Bypass Mode Gain Frequency Response&quot;&gt;
&lt;/p&gt;

### 6 Hz Resonant Amplification Validation (`DC_RMS_Oscillation_Normal.m`)

A 6 Hz, $`\pm 0.02 \mathrm{p.u.}`$ sinusoidal perturbation on $`\mathrm{p}_{\mathrm{chip},3\phi}`$ at $`f_{\mathrm{bw,vsi}}=25 \mathrm{Hz}`$ confirms strong grid-side amplification ($`4.64\times`$ EMT vs. $`5.23\times`$ RMS) in close phase alignment.

&lt;p align=&quot;center&quot;&gt;
  &lt;img src=&quot;docs/figures/Fig8_Normal_Oscillation_6Hz.png&quot; width=&quot;72%&quot; alt=&quot;6 Hz Amplification Validation&quot;&gt;
&lt;/p&gt;

## Citation

```
@article{Zhao2026DCRMS,
  author  = {Xingyu Zhao and Junbo Zhao and Yingyi Tang},
  title   = {Dynamic Modeling of Data Center Computing Loads for Power System Studies: From {EMT} to {RMS}},
  year    = {2026},
  note    = {Preprint / Under Review}
}

```
