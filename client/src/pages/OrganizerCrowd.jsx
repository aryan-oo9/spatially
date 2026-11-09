import { useEffect, useState, useCallback } from "react";
import { useAuth } from "../context/AuthContext";
import { useToast } from "../components/Toast";
import { api } from "../utils/api";
import { supabase, isSupabaseConfigured } from "../utils/supabaseClient";
import CrowdPredictionPanel from "../components/CrowdPredictionPanel";
import { 
  LuRadar, 
  LuMapPin, 
  LuTrendingUp, 
  LuTriangleAlert, 
  LuUsers, 
  LuClock,
  LuSlidersHorizontal,
  LuSave,
  LuSparkles,
  LuZap,
  LuArrowRight,
  LuStore,
  LuBell,
  LuBot,
  LuX,
  LuCheck,
  LuRefreshCw
} from "react-icons/lu";
import { 
  ResponsiveContainer, 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  Tooltip, 
  CartesianGrid 
} from "recharts";

export default function OrganizerCrowd() {
  const { user: _user } = useAuth();
  const toast = useToast();
  const [events, setEvents] = useState([]);
  const [selectedEventId, setSelectedEventId] = useState("");
  const [crowdData, setCrowdData] = useState(null);
  const [timelineData, setTimelineData] = useState([]);
  const [loading, setLoading] = useState(true);

  // Calibration state
  const [calibratingZoneId, setCalibratingZoneId] = useState(null);
  const [calibratedCount, setCalibratedCount] = useState("");
  const [calibratedNotes, setCalibratedNotes] = useState("");
  const [calibrating, setCalibrating] = useState(false);

  // AI Crowd Redistribution & Diversion Agent state
  const [diversionData, setDiversionData] = useState(null);
  const [autoDiversionLoading, setAutoDiversionLoading] = useState(false);
  const [dispatchModalOpen, setDispatchModalOpen] = useState(false);
  const [dispatching, setDispatching] = useState(false);
  const [selectedRec, setSelectedRec] = useState(null);
  const [customBonusPoints, setCustomBonusPoints] = useState(150);
  const [customTitle, setCustomTitle] = useState("");
  const [customDescription, setCustomDescription] = useState("");
  const [autoBroadcast, setAutoBroadcast] = useState(true);

  useEffect(() => {
    api.get("/api/events/organizer/mine")
      .then((data) => {
        const evList = data.events || [];
        setEvents(evList);
        if (evList.length > 0) {
          const liveEvent = evList.find(e => e.status === "live") || evList.find(e => e.status === "upcoming") || evList[0];
          setSelectedEventId(liveEvent.id);
        } else {
          setLoading(false);
        }
      })
      .catch((err) => {
        toast(err.message, "error");
        setLoading(false);
      });
  }, [toast]);

  const fetchCrowdData = useCallback(() => {
    if (!selectedEventId) return;
    Promise.all([
      api.get(`/api/organizer/crowd/${selectedEventId}`),
      api.get(`/api/organizer/timeline/${selectedEventId}`).catch(() => ({ timeline: [] })),
      api.get(`/api/organizer/crowd/${selectedEventId}/diversion-recommendations`).catch(() => null),
    ])
      .then(([cData, tData, dData]) => {
        setCrowdData(cData);
        if (dData) setDiversionData(dData);
        // Format timeline data for Recharts from real DB values
        const rawTimeline = tData.timeline || [];
        if (rawTimeline.length > 0) {
          setTimelineData(rawTimeline.map((item, idx) => ({
            time: item.time || `${idx * 5}m`,
            devices: item.devices ?? item.active_count ?? item.count ?? 0,
          })));
        } else {
          // Real baseline reflecting actual current crowd (0 if none)
          const count = cData?.total_devices ?? 0;
          setTimelineData([
            { time: "-20m", devices: count },
            { time: "-15m", devices: count },
            { time: "-10m", devices: count },
            { time: "-5m", devices: count },
            { time: "Now", devices: count },
          ]);
        }
      })
      .catch((err) => {
        toast(err.message, "error");
      })
      .finally(() => {
        setLoading(false);
      });
  }, [selectedEventId, toast]);

  useEffect(() => {
    fetchCrowdData();
    const interval = setInterval(fetchCrowdData, 10000);

    // Supabase Realtime CDC on crowd_zone_snapshots & activities
    let channel = null;
    if (isSupabaseConfigured && selectedEventId) {
      channel = supabase
        .channel(`org-crowd-${selectedEventId}`)
        .on("postgres_changes", { event: "*", schema: "public", table: "crowd_zone_snapshots", filter: `event_id=eq.${selectedEventId}` }, () => fetchCrowdData())
        .on("postgres_changes", { event: "*", schema: "public", table: "volunteer_counts", filter: `event_id=eq.${selectedEventId}` }, () => fetchCrowdData())
        .subscribe();
    }

    return () => {
      clearInterval(interval);
      if (channel) supabase.removeChannel(channel);
    };
  }, [selectedEventId, fetchCrowdData]);

  // Headcount Calibration submit
  const handleCalibrate = async (e, zoneId) => {
    e.preventDefault();
    if (!calibratedCount || isNaN(calibratedCount)) {
      toast("Please enter a valid count", "warning");
      return;
    }
    setCalibrating(true);
    try {
      await api.post(`/api/organizer/crowd/calibrate?event_id=${selectedEventId}`, {
        zone_id: zoneId,
        manual_count: parseInt(calibratedCount, 10),
        notes: calibratedNotes || "Manual turnstile recount",
      });
      toast("Manual calibration recorded!", "success");
      setCalibratingZoneId(null);
      setCalibratedCount("");
      setCalibratedNotes("");
      fetchCrowdData();
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setCalibrating(false);
    }
  };

  // Toggle Autonomous Crowd Diversion Agent
  const handleToggleAutoDiversion = async () => {
    if (!selectedEventId) return;
    const nextState = !diversionData?.auto_diversion_enabled;
    setAutoDiversionLoading(true);
    try {
      await api.post(`/api/organizer/crowd/${selectedEventId}/auto-diversion/toggle`, {
        enabled: nextState,
      });
      setDiversionData(prev => ({
        ...prev,
        auto_diversion_enabled: nextState,
      }));
      toast(
        nextState 
          ? "Autonomous Crowd Diversion Agent activated (Gemini 3.5 Flash Lite)" 
          : "Autonomous Crowd Diversion Agent paused",
        nextState ? "success" : "info"
      );
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setAutoDiversionLoading(false);
    }
  };

  // Open Modal to Dispatch a Diversion Quest
  const handleOpenDispatchModal = (rec) => {
    setSelectedRec(rec);
    const bonus = rec.suggested_bonus_points || 150;
    setCustomBonusPoints(bonus);
    setCustomTitle(`⚡ Flash Surge: Visit ${rec.sponsor.name} at ${rec.target_zone.name}!`);
    setCustomDescription(
      `Beat the crowd rush at ${rec.source_zone.name}! Head over to ${rec.target_zone.name} and check out the ${rec.sponsor.name} showcase ${rec.sponsor.booth_number ? `(${rec.sponsor.booth_number})` : ""}. Scan their checkpoint in the next 15 minutes to unlock +${bonus} BONUS Points!`
    );
    setAutoBroadcast(true);
    setDispatchModalOpen(true);
  };

  // Trigger Diversion directly for a specific zone
  const handleTriggerZoneDiversion = async (zoneId, zoneName) => {
    try {
      const q = zoneId ? `?source_zone_id=${zoneId}` : "";
      const data = await api.get(`/api/organizer/crowd/${selectedEventId}/diversion-recommendations${q}`);
      if (data.recommendations && data.recommendations.length > 0) {
        handleOpenDispatchModal(data.recommendations[0]);
      } else {
        toast(`No partner booths found to redirect from ${zoneName || "zone"}. Add brands in Brands & Sponsors Hub.`, "warning");
      }
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // Confirm and Broadcast Diversion Quest
  const handleConfirmDispatch = async (e) => {
    e?.preventDefault();
    if (!selectedRec || !selectedEventId) return;
    setDispatching(true);
    try {
      const payload = {
        event_id: selectedEventId,
        overcrowded_zone_id: selectedRec.source_zone.id,
        overcrowded_zone_name: selectedRec.source_zone.name,
        target_zone_id: selectedRec.target_zone.id,
        target_zone_name: selectedRec.target_zone.name,
        sponsor_id: selectedRec.sponsor.id,
        brand_name: selectedRec.sponsor.name,
        booth_number: selectedRec.sponsor.booth_number || "",
        bonus_points: parseInt(customBonusPoints, 10) || 150,
        custom_title: customTitle.trim() || undefined,
        custom_description: customDescription.trim() || undefined,
        auto_broadcast: autoBroadcast,
      };

      const res = await api.post(`/api/organizer/crowd/${selectedEventId}/dispatch-diversion-quest`, payload);
      toast(res.message || "Surge quest dispatched! Attendees incentivized to move.", "success");
      setDispatchModalOpen(false);
      fetchCrowdData();
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setDispatching(false);
    }
  };

  const getDensityColor = (current, capacity) => {
    if (!capacity) return "var(--info)";
    const ratio = current / capacity;
    if (ratio > 0.9) return "var(--error)";
    if (ratio > 0.75) return "var(--warning)";
    return "var(--success)";
  };

  const totalCrowd = crowdData?.zone_density 
    ? Object.values(crowdData.zone_density).reduce((sum, zone) => sum + (zone.active_count || 0), 0) 
    : 0;
  const totalCapacity = crowdData?.zone_density 
    ? Object.values(crowdData.zone_density).reduce((sum, zone) => sum + (zone.operating_capacity || 0), 0) 
    : 0;

  return (
    <div className="fade-in">
      <div className="page-header">
        <div>
          <h1 style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <div style={{ width: "12px", height: "12px", borderRadius: "50%", backgroundColor: "var(--success)", boxShadow: "0 0 10px var(--success)", animation: "pulse 2s infinite" }} />
            Live Crowd Telemetry & Telemetry Feed
          </h1>
          <p style={{ color: "var(--text-muted)", marginTop: "4px" }}>
            Real-time BLE presence signals, 5-minute rolling surge curves, and turnstile calibrations.
          </p>
        </div>
        <div style={{ display: "flex", gap: "12px" }}>
          {events.length > 0 && (
            <select 
              className="form-select" 
              value={selectedEventId} 
              onChange={(e) => setSelectedEventId(e.target.value)}
              style={{ minWidth: "220px" }}
            >
              {events.map(ev => (
                <option key={ev.id} value={ev.id}>{ev.name} ({ev.status})</option>
              ))}
            </select>
          )}
        </div>
      </div>

      {loading ? (
        <div style={{ padding: "40px", textAlign: "center" }}><div className="spinner"></div></div>
      ) : !crowdData ? (
        <div className="empty-state">
          <div className="empty-state-icon"><LuRadar /></div>
          <div className="empty-state-title">No telemetry data</div>
          <div className="empty-state-text">
            Start the event to begin collecting BLE presence data.
          </div>
        </div>
      ) : (
        <>
          {/* TOP METRICS */}
          <div className="stats-grid" style={{ marginBottom: "20px" }}>
            <div className="stat-card">
              <div className="stat-icon info"><LuUsers /></div>
              <div>
                <div className="stat-value">{totalCrowd}</div>
                <div className="stat-label">Active Presence (BLE Devices)</div>
              </div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ color: getDensityColor(totalCrowd, totalCapacity) }}><LuTrendingUp /></div>
              <div>
                <div className="stat-value">{totalCapacity > 0 ? Math.round((totalCrowd / totalCapacity) * 100) : 0}%</div>
                <div className="stat-label">Overall Venue Utilization</div>
              </div>
            </div>
            <div className="stat-card">
              <div className="stat-icon warning"><LuRadar /></div>
              <div>
                <div className="stat-value">{crowdData.raw_counts?.length || 0}</div>
                <div className="stat-label">Active Scanners Reporting</div>
              </div>
            </div>
          </div>

          {/* ══════════════════════════════════════════════════════════════════ */}
          {/* AI CROWD REDISTRIBUTION & SPONSOR DIVERSION HUB (GEMINI 3.5 FLASH LITE) */}
          {/* ══════════════════════════════════════════════════════════════════ */}
          <div 
            className="card" 
            style={{ 
              marginBottom: "24px", 
              padding: "22px",
              background: "linear-gradient(180deg, rgba(14, 165, 233, 0.06) 0%, rgba(15, 23, 42, 0.8) 100%)",
              border: "1px solid rgba(14, 165, 233, 0.3)",
              boxShadow: "0 8px 24px rgba(0, 0, 0, 0.25)",
              borderRadius: "12px",
              position: "relative"
            }}
          >
            {/* Header with Title and Autonomous Mode Toggle */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "16px", marginBottom: "18px" }}>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                  <div style={{ 
                    width: "34px", 
                    height: "34px", 
                    borderRadius: "8px", 
                    background: "rgba(14, 165, 233, 0.2)", 
                    display: "flex", 
                    alignItems: "center", 
                    justifyContent: "center",
                    color: "var(--primary)"
                  }}>
                    <LuSparkles size={18} />
                  </div>
                  <div>
                    <h3 style={{ fontSize: "1.1rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}>
                      AI Crowd Redistribution & Sponsor Diversion Engine
                      <span className="badge" style={{ background: "rgba(58, 114, 32, 0.2)", color: "var(--green-300)", fontSize: "0.7rem", padding: "2px 8px" }}>
                        Gemini 3.5 Flash Lite
                      </span>
                    </h3>
                    <p style={{ color: "var(--text-muted)", fontSize: "0.82rem", marginTop: "3px", margin: 0 }}>
                      When a venue area becomes overcrowded, the agent dispatches gamified quests incentivizing attendees to visit sponsor stalls in low-density zones.
                    </p>
                  </div>
                </div>
              </div>

              {/* Autonomous Mode Toggle */}
              <div style={{ display: "flex", alignItems: "center", gap: "12px", background: "var(--bg-secondary)", padding: "8px 14px", borderRadius: "8px", border: "1px solid var(--border-light)" }}>
                <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
                  <span style={{ fontSize: "0.75rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "6px" }}>
                    <LuBot size={14} color={diversionData?.auto_diversion_enabled ? "var(--green-400)" : "var(--text-muted)"} />
                    Autonomous Redistribution
                  </span>
                  <span style={{ fontSize: "0.68rem", color: diversionData?.auto_diversion_enabled ? "var(--green-400)" : "var(--text-muted)" }}>
                    {diversionData?.auto_diversion_enabled ? "Active (Auto-redirects at ≥85%)" : "Paused (Manual dispatch only)"}
                  </span>
                </div>

                <button
                  className={`btn btn-sm ${diversionData?.auto_diversion_enabled ? "btn-primary" : "btn-outline"}`}
                  style={{ fontSize: "0.78rem", padding: "5px 12px", display: "flex", alignItems: "center", gap: "6px" }}
                  onClick={handleToggleAutoDiversion}
                  disabled={autoDiversionLoading}
                >
                  {autoDiversionLoading ? (
                    <LuRefreshCw className="spin" size={13} />
                  ) : diversionData?.auto_diversion_enabled ? (
                    <><LuCheck size={14} /> Enabled</>
                  ) : (
                    "Enable Auto"
                  )}
                </button>
              </div>
            </div>

            {/* Recommendations Grid or Optimal Status Banner */}
            {diversionData?.recommendations && diversionData.recommendations.length > 0 ? (
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "12px" }}>
                  <span className="badge" style={{ background: "rgba(239, 68, 68, 0.15)", color: "#EF4444", fontSize: "0.75rem", display: "flex", alignItems: "center", gap: "5px" }}>
                    <LuTriangleAlert size={12} />
                    {diversionData.congested_zones_count || 1} Bottleneck Zone(s) Detected
                  </span>
                  <span style={{ fontSize: "0.8rem", color: "var(--text-secondary)" }}>
                    Recommended crowd diversion pairings to alleviate overcrowding:
                  </span>
                </div>

                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(360px, 1fr))", gap: "14px" }}>
                  {diversionData.recommendations.map((rec) => (
                    <div 
                      key={rec.id}
                      style={{
                        background: "rgba(15, 23, 42, 0.7)",
                        border: "1px solid rgba(255, 255, 255, 0.08)",
                        borderRadius: "10px",
                        padding: "16px",
                        display: "flex",
                        flexDirection: "column",
                        gap: "12px"
                      }}
                    >
                      {/* Source -> Destination visual flow */}
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px" }}>
                        {/* Overcrowded Source */}
                        <div style={{ flex: 1, background: "rgba(239, 68, 68, 0.1)", border: "1px solid rgba(239, 68, 68, 0.25)", borderRadius: "8px", padding: "8px 10px" }}>
                          <div style={{ fontSize: "0.7rem", color: "#EF4444", fontWeight: "700", textTransform: "uppercase" }}>Overcrowded</div>
                          <div style={{ fontSize: "0.9rem", fontWeight: "700", color: "#fff", display: "flex", alignItems: "center", gap: "4px" }}>
                            <LuMapPin size={13} color="#EF4444" /> {rec.source_zone.name}
                          </div>
                          <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                            {rec.source_zone.active_count} active ({Math.round(rec.source_zone.ratio * 100)}%)
                          </div>
                        </div>

                        {/* Arrow */}
                        <div style={{ color: "var(--primary)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                          <LuArrowRight size={20} />
                        </div>

                        {/* Low-Density Target Sponsor */}
                        <div style={{ flex: 1.2, background: "rgba(58, 114, 32, 0.1)", border: "1px solid rgba(58, 114, 32, 0.25)", borderRadius: "8px", padding: "8px 10px" }}>
                          <div style={{ fontSize: "0.7rem", color: "var(--green-400)", fontWeight: "700", textTransform: "uppercase" }}>Target Sponsor Stall</div>
                          <div style={{ fontSize: "0.9rem", fontWeight: "700", color: "#fff", display: "flex", alignItems: "center", gap: "4px" }}>
                            <LuStore size={13} color="var(--green-400)" /> {rec.sponsor.name}
                          </div>
                          <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                            in {rec.target_zone.name} • {Math.round(rec.target_zone.ratio * 100)}% density
                          </div>
                        </div>
                      </div>

                      {/* AI Reasoning Text */}
                      <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", lineHeight: "1.4", background: "rgba(255, 255, 255, 0.02)", padding: "8px 10px", borderRadius: "6px" }}>
                        {rec.reasoning}
                      </div>

                      {/* Footer: Bonus points and Dispatch Button */}
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", borderTop: "1px solid var(--border-light)", paddingTop: "10px", marginTop: "auto" }}>
                        <span className="badge" style={{ background: "rgba(245, 158, 11, 0.15)", color: "#F59E0B", fontWeight: "700", fontSize: "0.78rem" }}>
                          <LuZap size={13} /> +{rec.suggested_bonus_points} Surge Points
                        </span>

                        <button 
                          className="btn btn-sm btn-primary"
                          style={{ fontSize: "0.8rem", padding: "5px 14px", display: "flex", alignItems: "center", gap: "6px" }}
                          onClick={() => handleOpenDispatchModal(rec)}
                        >
                          <LuZap size={14} /> Dispatch Surge Quest
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "12px", background: "rgba(58, 114, 32, 0.08)", border: "1px solid rgba(58, 114, 32, 0.2)", borderRadius: "8px", padding: "12px 16px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                  <LuCheck size={18} color="var(--green-400)" />
                  <div>
                    <div style={{ fontSize: "0.85rem", fontWeight: "600", color: "#fff" }}>
                      Venue Crowd Flow is Balanced
                    </div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                      All monitored zones are currently operating within safe thresholds. Gemini AI is standing by to route crowd surges if any zone exceeds 85%.
                    </div>
                  </div>
                </div>

                <button 
                  className="btn btn-sm btn-ghost" 
                  style={{ fontSize: "0.78rem", display: "flex", alignItems: "center", gap: "6px" }}
                  onClick={() => handleTriggerZoneDiversion("", "")}
                >
                  <LuSparkles size={14} color="var(--primary)" /> Test Surge Dispatch
                </button>
              </div>
            )}
          </div>

          <CrowdPredictionPanel eventId={selectedEventId} />

          {/* 5-MINUTE ROLLING SURGE CHART */}
          <div className="card" style={{ marginBottom: "24px", padding: "20px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
              <h3 style={{ fontSize: "1rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "8px" }}>
                <LuTrendingUp size={18} color="var(--primary)" /> Rolling Attendance Surge Velocity
              </h3>
              <span className="badge info" style={{ fontSize: "0.75rem" }}>Live Stream (5m window)</span>
            </div>

            <div style={{ width: "100%", height: 180 }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={timelineData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                  <defs>
                    <linearGradient id="crowdGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#0EA5E9" stopOpacity={0.4} />
                      <stop offset="95%" stopColor="#0EA5E9" stopOpacity={0.0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
                  <XAxis dataKey="time" stroke="var(--text-muted)" fontSize={11} tickLine={false} />
                  <YAxis stroke="var(--text-muted)" fontSize={11} tickLine={false} />
                  <Tooltip 
                    contentStyle={{ backgroundColor: "#0F172A", borderColor: "rgba(255,255,255,0.1)", borderRadius: "8px", fontSize: "0.8rem" }}
                  />
                  <Area type="monotone" dataKey="devices" stroke="#0EA5E9" strokeWidth={2} fillOpacity={1} fill="url(#crowdGradient)" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* ZONE CARDS WITH STALENESS & CALIBRATION & AI CROWD RELIEF */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: "20px" }}>
            {Object.entries(crowdData.zone_density || {}).map(([zoneName, data]) => {
              const capacity = data.operating_capacity || data.capacity_limit || 0;
              const ratio = capacity > 0 ? (data.active_count || 0) / capacity : 0;
              const densityColor = getDensityColor(data.active_count, capacity);
              const isOvercrowded = ratio > 0.85;
              
              // Staleness indicator: if snapshot timestamp > 5 mins old
              const isStale = data.snapshot_at && (Date.now() - new Date(data.snapshot_at).getTime()) > 5 * 60 * 1000;
              const isCalibrating = calibratingZoneId === data.zone_id;

              return (
                <div 
                  key={zoneName} 
                  className="card" 
                  style={{ 
                    padding: "20px", 
                    border: isOvercrowded ? "1px solid var(--error)" : undefined,
                    opacity: isStale ? 0.75 : 1,
                    position: "relative"
                  }}
                >
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "14px" }}>
                    <div>
                      <h3 style={{ fontSize: "1.1rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "6px" }}>
                        <LuMapPin size={16} color="var(--primary)" />
                        {zoneName}
                      </h3>
                      <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", marginTop: "4px" }}>
                        {data.volunteer_scanners || 0} active volunteer scanner(s)
                      </div>
                    </div>

                    <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "4px" }}>
                      {isOvercrowded && (
                        <div className="badge" style={{ backgroundColor: "var(--error)", color: "#fff", display: "flex", alignItems: "center", gap: "4px" }}>
                          <LuTriangleAlert size={12} /> Bottleneck Peak
                        </div>
                      )}
                      {isStale && (
                        <span className="badge" style={{ backgroundColor: "rgba(245,158,11,0.2)", color: "#F59E0B", fontSize: "0.7rem" }} title="Telemetry not updated in >5 minutes">
                          <LuClock size={11} /> Stale &gt;5m
                        </span>
                      )}
                    </div>
                  </div>
                  
                  <div style={{ display: "flex", alignItems: "flex-end", gap: "8px", marginBottom: "12px" }}>
                    <div style={{ fontSize: "2.5rem", fontWeight: "800", lineHeight: "1", color: densityColor }}>
                      {data.active_count || 0}
                    </div>
                    <div style={{ fontSize: "0.9rem", color: "var(--text-muted)", paddingBottom: "4px" }}>
                      / {capacity > 0 ? capacity : "∞"} max capacity ({Math.round(ratio * 100)}%)
                    </div>
                  </div>
                  
                  {capacity > 0 && (
                    <div style={{ width: "100%", height: "8px", backgroundColor: "var(--bg-secondary)", borderRadius: "4px", overflow: "hidden", marginBottom: "14px" }}>
                      <div style={{ 
                        height: "100%", 
                        width: `${Math.min(ratio * 100, 100)}%`, 
                        backgroundColor: densityColor,
                        transition: "width 0.6s ease"
                      }} />
                    </div>
                  )}

                  {/* Zone Actions: Calibrate & AI Crowd Relief Button */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", borderTop: "1px solid var(--border-light)", paddingTop: "12px", gap: "8px" }}>
                    <button
                      className="btn btn-sm btn-ghost"
                      style={{ fontSize: "0.8rem", display: "flex", alignItems: "center", gap: "6px" }}
                      onClick={() => setCalibratingZoneId(isCalibrating ? null : data.zone_id)}
                    >
                      <LuSlidersHorizontal size={14} />
                      {isCalibrating ? "Close" : "Calibrate"}
                    </button>

                    <button
                      className="btn btn-sm btn-outline"
                      style={{ 
                        fontSize: "0.75rem", 
                        display: "flex", 
                        alignItems: "center", 
                        gap: "5px",
                        borderColor: isOvercrowded ? "var(--error)" : "rgba(14, 165, 233, 0.4)",
                        color: isOvercrowded ? "var(--error)" : "var(--primary)",
                        backgroundColor: isOvercrowded ? "rgba(239, 68, 68, 0.08)" : "transparent"
                      }}
                      onClick={() => handleTriggerZoneDiversion(data.zone_id, zoneName)}
                      title="Disperse attendees to an under-visited sponsor stall"
                    >
                      <LuSparkles size={13} />
                      {isOvercrowded ? "Relieve Congestion" : "AI Crowd Relief"}
                    </button>
                  </div>

                  {/* Manual Calibration Input Drawer */}
                  {isCalibrating && (
                    <form onSubmit={(e) => handleCalibrate(e, data.zone_id)} style={{ marginTop: "12px", background: "var(--bg-secondary)", padding: "12px", borderRadius: "8px" }}>
                      <div style={{ fontSize: "0.8rem", fontWeight: "700", marginBottom: "8px" }}>Manual Recount Override:</div>
                      <div style={{ display: "flex", gap: "8px", marginBottom: "8px" }}>
                        <input
                          type="number"
                          className="form-input"
                          placeholder="Turnstile Headcount"
                          value={calibratedCount}
                          onChange={(e) => setCalibratedCount(e.target.value)}
                          required
                          style={{ fontSize: "0.85rem", padding: "6px 10px" }}
                        />
                        <button type="submit" className="btn btn-sm btn-primary" disabled={calibrating}>
                          <LuSave size={14} /> {calibrating ? "..." : "Save"}
                        </button>
                      </div>
                      <input
                        type="text"
                        className="form-input"
                        placeholder="Notes (e.g. Gate 2 turnstile sync)"
                        value={calibratedNotes}
                        onChange={(e) => setCalibratedNotes(e.target.value)}
                        style={{ fontSize: "0.8rem", padding: "4px 8px" }}
                      />
                    </form>
                  )}

                </div>
              );
            })}
          </div>
        </>
      )}

      {/* ══════════════════════════════════════════════════════════════════ */}
      {/* DISPATCH CROWD SURGE DIVERSION QUEST MODAL */}
      {/* ══════════════════════════════════════════════════════════════════ */}
      {dispatchModalOpen && selectedRec && (
        <div className="modal-overlay fade-in" onClick={() => setDispatchModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "600px", maxHeight: "90vh", overflowY: "auto" }}>
            <div className="modal-header">
              <div>
                <h3 style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "1.15rem", margin: 0 }}>
                  <LuZap color="var(--primary)" size={20} /> Dispatch Crowd Relief Surge Quest
                </h3>
                <div style={{ display: "flex", alignItems: "center", gap: "6px", marginTop: "4px" }}>
                  <span style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>Engine:</span>
                  <span className="badge" style={{ background: "rgba(58, 114, 32, 0.2)", color: "var(--green-300)", fontSize: "0.7rem", padding: "1px 6px" }}>
                    Gemini 3.5 Flash Lite
                  </span>
                </div>
              </div>
              <button 
                className="btn-icon" 
                onClick={() => setDispatchModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>

            <form onSubmit={handleConfirmDispatch}>
              <div className="modal-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                {/* Visual Flow summary */}
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--bg-tertiary)", padding: "12px 14px", borderRadius: "8px" }}>
                  <div>
                    <div style={{ fontSize: "0.7rem", color: "#EF4444", fontWeight: "700" }}>CONGESTED SPOT</div>
                    <div style={{ fontSize: "0.95rem", fontWeight: "700" }}>{selectedRec.source_zone.name}</div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                      {selectedRec.source_zone.active_count} active attendees
                    </div>
                  </div>
                  <div style={{ color: "var(--primary)" }}><LuArrowRight size={22} /></div>
                  <div>
                    <div style={{ fontSize: "0.7rem", color: "var(--green-400)", fontWeight: "700" }}>DESTINATION SPONSOR</div>
                    <div style={{ fontSize: "0.95rem", fontWeight: "700" }}>{selectedRec.sponsor.name}</div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                      in {selectedRec.target_zone.name} ({selectedRec.sponsor.booth_number || "Stall"})
                    </div>
                  </div>
                </div>

                {/* Bonus Points Incentive Selector */}
                <div className="form-group">
                  <label className="form-label" style={{ display: "flex", justifyContent: "space-between" }}>
                    <span>Surge Bonus Reward Points *</span>
                    <span style={{ color: "var(--primary)", fontWeight: "700" }}>+{customBonusPoints} pts</span>
                  </label>
                  <div style={{ display: "flex", gap: "8px" }}>
                    {[100, 150, 200, 250].map((pts) => (
                      <button
                        key={pts}
                        type="button"
                        onClick={() => setCustomBonusPoints(pts)}
                        className={`btn btn-sm ${customBonusPoints === pts ? "btn-primary" : "btn-ghost"}`}
                        style={{ flex: 1, fontSize: "0.85rem" }}
                      >
                        +{pts} Pts
                      </button>
                    ))}
                  </div>
                </div>

                {/* Quest Title */}
                <div className="form-group">
                  <label className="form-label">Quest Notification Title *</label>
                  <input
                    type="text"
                    className="form-input"
                    value={customTitle}
                    onChange={(e) => setCustomTitle(e.target.value)}
                    required
                  />
                </div>

                {/* Quest Description */}
                <div className="form-group">
                  <label className="form-label">Attendee Instructions & Call to Action *</label>
                  <textarea
                    className="form-input"
                    rows={3}
                    value={customDescription}
                    onChange={(e) => setCustomDescription(e.target.value)}
                    required
                  />
                </div>

                {/* Push Notification Broadcast Checkbox */}
                <label style={{ display: "flex", alignItems: "center", gap: "10px", cursor: "pointer", background: "rgba(14, 165, 233, 0.08)", padding: "10px 12px", borderRadius: "8px", border: "1px solid rgba(14, 165, 233, 0.2)" }}>
                  <input
                    type="checkbox"
                    checked={autoBroadcast}
                    onChange={(e) => setAutoBroadcast(e.target.checked)}
                    style={{ width: "16px", height: "16px" }}
                  />
                  <div>
                    <div style={{ fontSize: "0.85rem", fontWeight: "600", display: "flex", alignItems: "center", gap: "6px" }}>
                      <LuBell size={14} color="var(--primary)" /> Real-Time Push Notification
                    </div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>
                      Broadcasts instant mobile alert to attendees via Supabase Realtime channel.
                    </div>
                  </div>
                </label>
              </div>

              <div className="modal-footer" style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "16px" }}>
                <button 
                  type="button" 
                  className="btn btn-ghost" 
                  onClick={() => setDispatchModalOpen(false)}
                >
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className="btn btn-primary" 
                  disabled={dispatching}
                  style={{ display: "flex", alignItems: "center", gap: "6px" }}
                >
                  {dispatching ? (
                    <><LuRefreshCw className="spin" size={14} /> Dispatching...</>
                  ) : (
                    <><LuZap size={14} /> Confirm & Dispatch Surge Quest</>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
}
