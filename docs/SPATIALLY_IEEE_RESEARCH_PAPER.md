# Spatially: Privacy-Preserving BLE Telemetry and Macroscopic Graph Forecasting for Venue Crowd Management

**Aryan Verma**  
*Computer Engineering Department, Fr. Conceicao Rodrigues College of Engineering*  
`aryanverma1750@gmail.com`

**Blaise Rodrigues**  
*Computer Engineering Department, Fr. Conceicao Rodrigues College of Engineering*  
`blaiserods26@gmail.com`

**Daksh Thakar**  
*Computer Engineering Department, Fr. Conceicao Rodrigues College of Engineering*  
`dakshthakkar296@gmail.com`

**Devansh Nayak**  
*Computer Engineering Department, Fr. Conceicao Rodrigues College of Engineering*  
`devanshnayak2006@gmail.com`

**Prof. Ankita Amburle**  
*Computer Engineering Department, Fr. Conceicao Rodrigues College of Engineering*  
`ankita.amburle@fragnel.edu.in`

---

## Abstract
Managing crowd safety across large-scale indoor and multi-level venues remains a major public safety challenge. Conventional monitoring systems rely either on privacy-invasive camera or Media Access Control (MAC) surveillance, or on deep learning models that suffer from cold-start failures in temporary venues lacking historical training data. Furthermore, existing event dashboards operate reactively and lack closed-loop mechanisms to redistribute foot traffic. This paper presents *Spatially*, an end-to-end, privacy-preserving event intelligence and crowd coordination platform uniting attendee mobile, volunteer mobile, and organizer web command surfaces. Spatially introduces three technical contributions: (1) a Bluetooth Low Energy (BLE) telemetry pipeline free of personally identifiable information (PII), using rotating 6-byte SHA-256 ephemeral identifiers, sticky service-UUID filtering, and an offline-resilient local relational outbox; (2) a training-free, three-layer macroscopic overcrowding predictor combining irregular-interval Holt exponential smoothing, floorplan-derived topology graphs, mass-conserving hydraulic spillover, and timetable-driven session surges; and (3) a closed-loop mitigation architecture pairing non-visual volunteer waveform haptics with generative AI surge-diversion tasks to incentivize voluntary attendee dispersal. Evaluation across 205 mobile tests, Android hardware trials, and multi-scale benchmarks demonstrates 25-zone, 15 min horizon inference in 0.751 ms (4.724 ms for 100 zones), exact mass conservation ($<10^{-6}$ residual), and 12.3 min early-warning lead times.

**Keywords:** Bluetooth Low Energy, Crowd Monitoring, Data Privacy, Exponential Smoothing, Graph Theory, Indoor Environments, Pedestrian Traffic, Public Safety.

---

## I. Introduction
Large-scale physical gatherings—such as technical conferences, stadium exhibitions, multi-track conventions, and music festivals—transform constrained architectural spaces into high-density, rapidly evolving pedestrian networks. As global urbanization and event attendance intensify, preventing localized overcrowding and crowd-crush incidents has become a major public safety requirement [1], [2]. Forensic analyses of recent high-density pedestrian disasters, including the 2022 Itaewon crowd crush, reveal that fatal congestion rarely occurs instantaneously; rather, it is preceded by a 15–30 min accumulation window during which localized pedestrian inflows consistently exceed structural egress capacities [2], [3]. Consequently, shifting event operations from retrospective observation to proactive, short-horizon anticipation (5–20 min ahead) is essential to provide safety directors and on-ground staff with the operational buffer required to throttle gate admissions, stage personnel, and redirect foot traffic [4], [5].

Despite extensive research in pedestrian dynamics and indoor positioning, deploying real-time crowd intelligence in temporary or reconfigurable event venues presents four fundamental systems engineering challenges:
1. **The Privacy-Surveillance Dichotomy:** Camera-based computer vision (CV) counting networks and passive Wi-Fi or Bluetooth Media Access Control (MAC) sniffers expose attendees to persistent biometric or hardware-level trajectory tracking, violating modern data protection frameworks and eroding user trust [6], [7]. Conversely, modern mobile operating systems randomize hardware MAC addresses at unpredictable intervals, corrupting naive scanner headcounts via double-counting or premature expiry.
2. **The Cold-Start and Edge Compute Bottleneck:** Deep spatio-temporal neural networks (such as ConvLSTMs and Graph Attention Networks) require months of historical sensor traces to learn venue-specific flow transitions [8], [9]. However, conventions and pop-up exhibitions feature bespoke booth layouts, temporary partitions, and one-off session timetables for which zero historical training data exist [4]. Moreover, parameter-heavy neural models impose prohibitive inference latency and memory overhead on edge and mid-tier cloud infrastructure [10].
3. **Intermittent Venue Connectivity:** High attendee density saturates local cellular towers and venue Wi-Fi access points. Operational telemetry, Quick Response (QR) ticket admissions, and incident dispatches that rely on synchronous cloud round-trips suffer from dropped packets, race conditions, and inconsistent state during peak ingress surges.
4. **Open-Loop Operational Silos:** Traditional crowd monitoring dashboards terminate at passive visualization [5]. Even when an organizer observes an impending bottleneck on a heatmap, translating that insight into physical crowd dispersal requires slow, manual radio coordination and lacks direct behavioral incentives for attendees.

To address these challenges, this paper presents **Spatially**, a unified, privacy-preserving event operations and spatial crowd intelligence platform. Spatially bridges three distinct client and control tiers over a shared, Row-Level Security (RLS)-hardened relational real-time backend: (1) an *Attendee Mobile Client*, (2) a *Volunteer Staff Mobile Client*, and (3) an *Organizer Command Web Portal and Intelligence Engine*.

The primary contributions of this work are as follows:
- **A Zero-PII, Offline-Resilient BLE Crowd Sensing Architecture:** We design and implement a cross-layer Bluetooth Low Energy (BLE) mobile telemetry protocol free of personally identifiable information (PII), combining rotating 6-byte SHA-256 ephemeral advertising, sticky Universally Unique Identifier (UUID) classification to overcome Android scan-response fragmentation, a 10 s deduplication and 45 s expiry window, and a durable local relational write-behind outbox with row-locked atomic ticket reconciliation (Section III).
- **A Training-Free, Mass-Conserving Macroscopic Graph Predictor:** We formulate a three-layer deterministic forecasting algorithm that couples irregular-interval Holt linear smoothing with boundary-derived zone graphs, capacity-headroom-weighted hydraulic spillover, and exogenous session schedule covariance, achieving sub-millisecond inference without historical training data (Section IV).
- **Closed-Loop Socio-Technical Crowd Actuation:** We introduce a dual-channel mitigation paradigm combining a deduplicated volunteer attention router (featuring non-visual tactile Android haptics and atomic shift-coverage state machines) with a generative AI and heuristic task-generation agent that incentivizes voluntary crowd dispersion via time-bounded redirection tasks (Section V).
- **Comprehensive Empirical and Hardware Validation:** We evaluate Spatially across 205 automated mobile unit and integration tests, physical Android hardware field trials, and multi-scale simulation benchmarks, demonstrating sub-5 ms scalability up to 100 zones, exact pedestrian mass conservation, and 12.3 min early-warning lead times on multi-hop keynote dispersal bottlenecks (Section VI).

---

## II. Related Work

| Study | Sensing | No-Train | Graph Flow | Actuation |
| :--- | :---: | :---: | :---: | :---: |
| Yasufuku [5] | LiDAR | Yes | No | Dashboard |
| Bohnet [11] | Camera | No | PDE | None |
| Duan [9] | Cellular | No | Grid CNN | None |
| CPMS-Net [10] | RGB Cam | No | Multi-Scale | None |
| Daamen [4] | Sensors | Yes | Corridor | Advisory |
| Jeong [14] | Beacons | Partial | Grid Twin | Alerting |
| **Spatially** | **BLE+QR** | **Yes** | **2-Hop+Sched** | **Haptic+AI** |

---

## III. System Architecture and Privacy-Preserving Telemetry
Spatially is architected as a four-tier cyber-physical system comprising two mobile edge clients (an attendee client and a volunteer staff client), a web-based operational command portal tracking Point of Interest (POI) layouts and Incident Service-Level Agreement (SLA) metrics—specifically Mean Time to Acknowledge (MTTA) and Mean Time to Resolve (MTTR)—a stateless forecasting and task-generation service, and a shared PostgreSQL backend enforcing RLS, transactional Remote Procedure Calls (RPCs), and Change Data Capture (CDC) real-time broadcast channels.

### A. Ephemeral BLE Advertising and Sticky Scanner Filtering
Upon initialization, the attendee client generates a random UUID v4 seed $u_d$ stored strictly in device-local preferences. During an active event, an Android foreground service broadcasts a low-power BLE advertisement carrying a dedicated 128-bit service UUID and a 6-byte manufacturer-specific payload under test company identifier `0xFFFF`. The 6-byte ephemeral beacon hash $b_t$ is derived via a rolling cryptographic digest over $u_d$ and the quantized time epoch $\tau_t = \lfloor t / \tau_{\mathrm{rot}} \rfloor$:

$$b_t = \mathrm{Trunc}_{48}\!\left(\mathrm{SHA\text{-}256}(u_d \parallel \tau_t)\right)$$

where $\mathrm{Trunc}_{48}(\cdot)$ extracts the leading 48 bits and $\tau_{\mathrm{rot}} \in [5, 15]$ min denotes the identifier rotation period.

On-duty volunteers execute a foreground BLE scanner service on Android hardware:
1. **Signal Sanity and Ephemeral Extraction:** Scan results with Received Signal Strength Indicator ($\mathrm{RSSI}$) $= -128$ dBm are discarded. If the `0xFFFF` frame has length 6 bytes, the 48-bit payload is extracted as candidate identifier $b_t$.
2. **Sticky Service-UUID Classification:** Once a candidate identifier $b_t$ is observed advertising the platform service UUID in any primary or scan-response packet, it is cached in a confirmed in-memory set until presence expiry. All ambient Bluetooth devices lacking the service UUID are dropped at the privacy gate prior to queueing.
3. **Deduplication and Presence Expiry Window:** The scanner enforces a deduplication window $\tau_{\mathrm{dedup}} = 10$ s and a presence timeout $\tau_{\mathrm{exp}} = 45$ s, evicting expired identifiers every 10 s.

### B. Offline-Resilient Write-Behind Outbox and Atomic Ticketing
Spatially prevents operational data loss during venue Wi-Fi outages via a local relational write-behind outbox on the volunteer device. The outbox buffers BLE headcount observations (flushed every 15–30 s to the cloud telemetry ledger) alongside offline ticket check-ins. When connectivity is available, QR ticket admissions invoke a transactional database RPC that acquires an exclusive row-level lock (`FOR UPDATE`) on the ticket record, preventing concurrent double-entry across parallel turnstiles.

---

## IV. Macroscopic Overcrowding Prediction Engine

### Summary of Mathematical Notation
| Symbol | Definition |
| :--- | :--- |
| $b_t,\ \tau_{\mathrm{rot}}$ | 48-bit rotating BLE beacon hash and rotation period (min) |
| $\tau_{\mathrm{dedup}},\ \tau_{\mathrm{exp}}$ | BLE scanner deduplication (10 s) and expiry (45 s) windows |
| $\mathcal{Z},\ N,\ |\mathcal{E}|$ | Monitored zone set $\{1,\dots,N\}$, zone count, and graph edge count |
| $B_i,\ \ell_i,\ C_i$ | Normalized 2D bounds $[0,1]^2$, floor level, and capacity of zone $i$ |
| $\tilde{w}_{ij},\ w_{ij}$ | Unnormalized and row-normalized boundary conductance $i \to j$ |
| $L_i,\ v_i,\ \bar{v}_i$ | Smoothed headcount, Holt velocity (/min), and effective velocity |
| $\Lambda_i^{(0)},\ \Lambda_i^{(1)},\ \Lambda_i^*$ | Layer-1 linear, gate-augmented, and final projected occupancy |
| $\lambda_i,\ S_i$ | Gate check-in arrival rate (/min) and scheduled session surge |
| $f_{i \to j}(M)$ | Mass-conserving crowd flow transfer of mass $M$ along edge $(i,j)$ |
| $q_{i,\mathrm{crit}},\ q_{i,\mathrm{leak}}$ | Critical excess load above $\theta_{i,\mathrm{crit}}C_i$ and busy-zone leakage load |
| $r_{i,\mathrm{cur}},\ r_{i,\mathrm{proj}}$ | Current ($L_i/C_i$) and projected ($\Lambda_i^*/C_i$) occupancy ratios |
| $\mathcal{R}_i,\ \mathrm{ETA}_i$ | Discrete zone risk tier and estimated time-to-warning breach (min) |
| $\phi(a_i),\ \kappa_i$ | Telemetry freshness factor at age $a_i$ and forecast confidence $[0.15,1]$ |

### A. Stage 1: Automatic Spatial Topology Graph Construction
Each zone $i \in \mathcal{Z}$ resides on floor level $\ell_i \in \mathbb{Z}^+$ and is bounded on $[0, 1]^2$ by:

$$B_i = [x_{i,\min},\, x_{i,\max}] \times [y_{i,\min},\, y_{i,\max}]$$

With $o_{\min} = \min(o_x, o_y)$, $o_{\max} = \max(o_x, o_y)$, and tolerance $\epsilon_{\mathrm{adj}} = 0.02$, the unnormalized shared-border conductance $\tilde{w}_{ij}$ is:

$$\tilde{w}_{ij} = \begin{cases} \epsilon_{\mathrm{adj}}, & \text{if } -\epsilon_{\mathrm{adj}} \le o_{\min} < 0, \\ \max(o_{\max}, \epsilon_{\mathrm{adj}}), & \text{if } o_{\min} \ge 0, \\ 0, & \text{otherwise.} \end{cases}$$

Cross-level vertical connectors inject explicit edges with $\tilde{w}_{ij} = 0.10$, and conductances are row-normalized per source zone:

$$w_{ij} = \frac{\tilde{w}_{ij}}{\sum_{k \in \mathcal{N}(i)} \tilde{w}_{ik}}, \quad \forall j \in \mathcal{N}(i)$$

### B. Stage 2: Irregular-Interval Holt Linear Trend Smoothing
With elapsed step $\Delta t_k = \max((t_{i,k} - t_{i,k-1})/60, 10^{-3})$ min, $\alpha = 0.5$, and $\beta = 0.3$:

$$\begin{aligned}
\hat{y}_{i,k} &= L_{i,k-1} + v_{i,k-1} \Delta t_k, \\
L_{i,k} &= \alpha y_{i,k} + (1 - \alpha)\hat{y}_{i,k}, \\
v_{i,k} &= \beta \left(\frac{L_{i,k} - L_{i,k-1}}{\Delta t_k}\right) + (1 - \beta)v_{i,k-1}, \\
\Lambda_i^{(0)}(t + H) &= \max(L_i + v_i H,\, 0).
\end{aligned}$$

### C. Stage 3: Mass-Conserving Graph Flow Propagation
Adding gate check-in arrivals $\lambda_i$ yields $\Lambda_i^{(1)} = \Lambda_i^{(0)}(t + H) + \lambda_i H$. Outgoing crowd mass $M > 0$ from zone $i$ into $\mathcal{N}(i)$ is distributed proportionally to conductance times destination free headroom:

$$\begin{aligned}
s_{ij} &= w_{ij}\big(\max(C_j - \Lambda_j,\, 0) + \varepsilon_0\big), \\
f_{i \to j}(M) &= M \cdot \frac{s_{ij}}{\sum_{k \in \mathcal{N}(i)} s_{ik}}.
\end{aligned}$$

Across $K=2$ hops, critical excess $q_{i,\mathrm{crit}}$ and busy-zone leakage $q_{i,\mathrm{leak}}(h)$ spill into $\mathcal{N}(i)$:

$$\begin{aligned}
q_{i,\mathrm{crit}} &= \max\!\big(\Lambda_i - \theta_{i,\mathrm{crit}} C_i,\, 0\big), \\
q_{i,\mathrm{leak}}(h) &= \mathbb{I}(h=0)\,\mathbb{I}(\Lambda_i \ge \rho_{\mathrm{leak}} C_i)\,\eta_{\mathrm{leak}}\max(v_i, 0)H, \\
M_{\mathrm{spill}}(i, h) &= \min\!\big(\Lambda_i,\; q_{i,\mathrm{crit}} + q_{i,\mathrm{leak}}(h)\big).
\end{aligned}$$

### D. Stage 4: Risk Scoring, ETA, and Confidence Calibration
With $\theta_{i,\mathrm{warn}} = 0.80$, $\theta_{i,\mathrm{crit}} = 0.90$, and $\theta_{i,\mathrm{watch}} = 0.65$:

$$\mathcal{R}_i = \begin{cases}
\texttt{critical}, & \text{if } r_{i,\mathrm{peak}} \ge \theta_{i,\mathrm{crit}}, \\
\texttt{warning}, & \text{if } \theta_{i,\mathrm{warn}} \le r_{i,\mathrm{peak}} < \theta_{i,\mathrm{crit}}, \\
\texttt{watch}, & \text{if } \theta_{i,\mathrm{watch}} \le r_{i,\mathrm{peak}} < \theta_{i,\mathrm{warn}}, \\
\texttt{normal}, & \text{otherwise.}
\end{cases}$$

Letting $\Omega_i = \theta_{i,\mathrm{warn}} C_i$ and $\bar{v}_i = (\Lambda_i^* - L_i)/H$:

$$\mathrm{ETA}_i = \begin{cases}
0.0, & \text{if } L_i \ge \Omega_i, \\
\min\!\left(\dfrac{\Omega_i - L_i}{\bar{v}_i},\, H\right), & \text{if } L_i < \Omega_i \le \Lambda_i^*, \\
\texttt{None}, & \text{otherwise.}
\end{cases}$$

---

## V. Closed-Loop Operational Actuation and Crowd Redirection

### A. Deterministic Volunteer Attention Routing and Haptics
The volunteer client synthesizes broadcasts, incidents, coverage requests, and zone alerts into a unified, deduplicated feed scored by relevance:

$$\mathrm{Rel}(e, v) = \begin{cases}
\texttt{assignedZone}, & \text{if } e.\mathrm{zone} = v.\mathrm{zone}, \\
\texttt{eventUrgent}, & \text{if } e.\mathrm{priority} = \texttt{urgent}, \\
\texttt{assignedTeam}, & \text{if } e.\mathrm{team} = v.\mathrm{team}, \\
\texttt{routine}, & \text{otherwise.}
\end{cases}$$

A tactile notification service drives distinct Android vibration waveforms for each relevance tier so field staff can distinguish urgent zone surges without visual screen inspection, while atomic shift-coverage RPCs prevent unstaffed monitoring gaps during handoffs.

### B. Generative AI and Heuristic Surge-Diversion Tasks
To incentivize voluntary attendee dispersal from a congested source zone $z_{\mathrm{src}}$ toward a high-headroom destination zone $z_{\mathrm{dst}}$, the command portal invokes the surge-diversion agent. The agent cascades across lightweight large language models (Gemini Flash variants) with a zero-latency deterministic template fallback to issue time-bounded redirection tasks offering $+150$ bonus experience points (XP, displayed as `pts` in the mobile interface) upon QR verification at a designated booth in $z_{\mathrm{dst}}$.

---

## VI. Experimental Evaluation and Results

### A. Canonical Crowd Pattern Evaluation ($H = 15$ min)
| Zone | Regime | $r_{\mathrm{cur}}$ | $v_i$ (/min) | $r_{\mathrm{proj}}$ | Risk (Lead, min) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| Zone 0 | `ramp` | 0.917 | $+3.35$ | 0.900 | `critical` (**8.4**) |
| Zone 1 | `surge` | 0.899 | $+6.72$ | 0.903 | `critical` (**5.2**) |
| Zone 2 | `dispersal` | 0.149 | $-9.30$ | 0.785 | `watch` (Spill) |
| Zone 3 | `plateau` | 0.400 | $-0.68$ | 0.297 | `normal` (`None`) |

### B. Ablation Study: Multi-Zone Keynote Dispersal
| Configuration | Main Hall | Foyer | ETA (min) | Expo A |
| :--- | :---: | :---: | :---: | :---: |
| 1. Reactive Baseline | 0.95 (`critical`) | 0.45 (`normal`) | `None` | 0.27 (`normal`) |
| 2. L1 Isolated Holt | 0.99 (`critical`) | 0.60 (`normal`) | `None` | 0.29 (`normal`) |
| 3. L1+L2 Graph Spill | 0.90 (`critical`) | 0.77 (`watch`) | `None` | 0.31 (`normal`) |
| **4. Full Spatially** | **0.63 (`critical`)** | **0.88 (`warning`)** | **12.3** | **0.66 (`watch`)** |

### C. Computational Latency and Subsystem Verification
| Zones ($N$) | Edges ($\|\mathcal{E}\|$) | Latency (ms) | Throughput (calls/s) |
| :---: | :---: | :---: | :---: |
| 5 | 8 | 0.113 | 8,849 |
| 10 | 18 | 0.236 | 4,237 |
| 25 | 68 | 0.751 | 1,331 |
| 50 | 150 | 1.916 | 522 |
| 100 | 324 | 4.724 | 212 |

End-to-end subsystem verification achieved a 100% pass rate across 205 automated mobile unit and integration tests (81/81 in the attendee client, 124/124 in the volunteer client), 12 backend test suites, and 46 physical field verification states on Android hardware (Nothing Phone A059P).

---

## VII. Discussion and Limitations
Several methodological and operational limitations bound the findings of this study:
1. **Synthetic Evaluation Traces and Single-Venue Topology:** While the BLE scanner, offline SQLite outbox, and tactile routing subsystems were verified on physical Android hardware, the canonical regime and keynote dispersal ablation benchmarks rely on calibrated synthetic crowd trajectories over a single multi-zone convention topology. Deploying overhead optical ground-truth counters across diverse architectural typologies (such as multi-tier stadiums and outdoor festival grounds) is required to quantify forecasting error distributions under real-world sensor noise.
2. **Unproven Behavioral Compliance Assumption:** The bottom-up actuation loop assumes that issuing $+150$ pt redirection tasks induces a non-trivial fraction of attendees to vacate congested zones. However, empirical compliance elasticity under real crowd stress, attendee fatigue, or high-interest keynote transitions has not yet been measured in live human-subject trials; consequently, gamified redirection should be treated as an advisory supplement to physical gate throttling and staff staging rather than a standalone safety control.
3. **Residual Physical and Link-Layer Privacy Boundaries:** Rotating the 48-bit SHA-256 payload $b_t$ every $\tau_{\mathrm{rot}} \in [5, 15]$ min prevents application-layer identity linkage and eliminates persistent PII in cloud storage. Nevertheless, if the underlying mobile operating system rotates its BLE link-layer random MAC address on a schedule asynchronous with $\tau_{\mathrm{rot}}$, a passive adversary operating collocated packet sniffers could correlate consecutive epochs across the non-rotating window, or apply physical-layer radio-frequency fingerprinting.
4. **Sensing Coverage and Geometric Approximation:** Incomplete attendee app penetration and temporary volunteer absence can bias raw BLE headcounts; Spatially partially mitigates these gaps by fusing QR turnstile check-in rates ($\lambda_i$) at entrance zones and decaying forecast confidence $\kappa_i$ to $0.3$ during scanner blackouts rather than extrapolating stale trends. Finally, the axis-aligned bounding rectangle model ($B_i \subset [0,1]^2$) overestimates conductance when non-porous walls separate adjacent zones, requiring manual edge overrides in the venue editor.

---

## VIII. Conclusion and Future Work
This paper presented **Spatially**, an end-to-end, privacy-preserving event operations and crowd intelligence platform. By uniting rotating 6-byte SHA-256 BLE telemetry, offline-resilient local relational outboxes, a sub-millisecond macroscopic graph flow predictor, and closed-loop volunteer haptics with incentivized redirection tasks, Spatially shifts physical venue management from reactive observation to proactive socio-technical coordination. Future work will investigate online recursive calibration of zone smoothing parameters $(\alpha, \beta)$ against optical ground truth and controlled field studies measuring attendee compliance elasticity across variable incentive rewards.

---

## Appendix: Implementation Mapping
| Conceptual Component | Repository Module / Schema Identifier |
| :--- | :--- |
| Attendee / Volunteer clients | `attendee_mobile/`, `volunteer_mobile/` |
| Organizer web command | `client/` (React 19, Vite, SVG editor) |
| BLE scanner & sticky set | `BleScannerService`, `_confirmedSpatiallyIds` |
| Local SQLite v7 outbox | `spatially_queue.db` (`observation_queue`) |
| Tactile attention router | `HapticAttentionService` |
| Spatial topology tables | `venues`, `venue_levels`, `venue_zones`, `event_zones` |
| Telemetry & state tables | `volunteer_counts`, `crowd_zone_snapshots`, `tickets` |
| Ops & shift RPCs | `check_in_ticket`, `request/accept_shift_coverage` |
| Macroscopic predictor | `server/app/services/crowd_prediction.py` |
| Surge-diversion agent | `server/app/services/quest_agent.py` |
