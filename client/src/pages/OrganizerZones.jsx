import { useEffect, useState, useCallback } from "react";
import { useAuth } from "../context/AuthContext";
import { useToast } from "../components/Toast";
import { api } from "../utils/api";
import { 
  LuMap, 
  LuPlus, 
  LuPencil, 
  LuTrash2, 
  LuSlidersHorizontal, 
  LuLayers, 
  LuShieldAlert, 
  LuLock, 
  LuCircleCheck,
  LuX
} from "react-icons/lu";

const OPERATIONAL_STATUSES = [
  { value: "open", label: "Open / Normal", color: "var(--success)" },
  { value: "restricted_staff_only", label: "Restricted (Staff Only)", color: "var(--warning)" },
  { value: "temporarily_closed_cleaning", label: "Temporarily Closed (Maintenance)", color: "var(--info)" },
  { value: "emergency_evacuated", label: "Emergency Evacuated", color: "var(--error)" },
];

export default function OrganizerZones() {
  const { user: _user } = useAuth();
  const toast = useToast();
  const [events, setEvents] = useState([]);
  const [selectedEventId, setSelectedEventId] = useState("");
  const [zones, setZones] = useState([]);
  const [levels, setLevels] = useState([]);
  const [loading, setLoading] = useState(true);

  // Modal & Form state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingZone, setEditingZone] = useState(null);
  const [errors, setErrors] = useState({});
  const [formData, setFormData] = useState({
    name: "",
    code: "",
    capacity_limit: "",
    operating_capacity: "",
    level_id: "",
    advisory_threshold: 0.70,
    warning_threshold: 0.85,
    critical_threshold: 0.95,
    operational_status: "open",
    is_crowd_monitored: true,
  });

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

  const fetchZonesAndLevels = useCallback(() => {
    if (!selectedEventId) return;
    setLoading(true);
    Promise.all([
      api.get(`/api/organizer/zones/${selectedEventId}`),
      api.get(`/api/venue-map/${selectedEventId}/levels`).catch(() => ({ levels: [] })),
    ])
      .then(([zData, lData]) => {
        setZones(zData.zones || []);
        setLevels(lData.levels || []);
      })
      .catch((err) => toast(err.message, "error"))
      .finally(() => setLoading(false));
  }, [selectedEventId, toast]);

  useEffect(() => {
    fetchZonesAndLevels();
  }, [fetchZonesAndLevels]);

  const handleOpenCreate = () => {
    setEditingZone(null);
    setErrors({});
    setFormData({
      name: "",
      code: "",
      capacity_limit: "",
      operating_capacity: "",
      level_id: levels.length > 0 ? levels[0].id : "",
      advisory_threshold: 0.70,
      warning_threshold: 0.85,
      critical_threshold: 0.95,
      operational_status: "open",
      is_crowd_monitored: true,
    });
    setIsModalOpen(true);
  };

  const handleOpenEdit = (zone) => {
    setEditingZone(zone);
    setErrors({});
    setFormData({
      name: zone.name || "",
      code: zone.code || "",
      capacity_limit: zone.capacity_limit != null ? zone.capacity_limit : "",
      operating_capacity: zone.operating_capacity != null ? zone.operating_capacity : "",
      level_id: zone.level_id || "",
      advisory_threshold: zone.advisory_threshold ?? 0.70,
      warning_threshold: zone.warning_threshold ?? 0.85,
      critical_threshold: zone.critical_threshold ?? 0.95,
      operational_status: zone.operational_status || "open",
      is_crowd_monitored: zone.is_crowd_monitored ?? true,
    });
    setIsModalOpen(true);
  };

  const handleAdvisoryChange = (val) => {
    const adv = parseFloat(val);
    setFormData((prev) => {
      const updated = { ...prev, advisory_threshold: adv };
      if (prev.warning_threshold <= adv) {
        updated.warning_threshold = Math.min(0.95, parseFloat((adv + 0.05).toFixed(2)));
      }
      if (prev.critical_threshold <= updated.warning_threshold) {
        updated.critical_threshold = Math.min(1.0, parseFloat((updated.warning_threshold + 0.05).toFixed(2)));
      }
      return updated;
    });
    if (errors.thresholds) setErrors((prev) => ({ ...prev, thresholds: null }));
  };

  const handleWarningChange = (val) => {
    const warn = parseFloat(val);
    setFormData((prev) => {
      const updated = { ...prev, warning_threshold: warn };
      if (warn <= prev.advisory_threshold) {
        updated.advisory_threshold = Math.max(0.1, parseFloat((warn - 0.05).toFixed(2)));
      }
      if (prev.critical_threshold <= warn) {
        updated.critical_threshold = Math.min(1.0, parseFloat((warn + 0.05).toFixed(2)));
      }
      return updated;
    });
    if (errors.thresholds) setErrors((prev) => ({ ...prev, thresholds: null }));
  };

  const handleCriticalChange = (val) => {
    const crit = parseFloat(val);
    setFormData((prev) => {
      const updated = { ...prev, critical_threshold: crit };
      if (crit <= prev.warning_threshold) {
        updated.warning_threshold = Math.max(0.2, parseFloat((crit - 0.05).toFixed(2)));
      }
      if (updated.warning_threshold <= prev.advisory_threshold) {
        updated.advisory_threshold = Math.max(0.1, parseFloat((updated.warning_threshold - 0.05).toFixed(2)));
      }
      return updated;
    });
    if (errors.thresholds) setErrors((prev) => ({ ...prev, thresholds: null }));
  };

  const handleDeleteZone = async (zoneId, zoneName) => {
    if (!window.confirm(`Are you sure you want to delete zone "${zoneName}"? This will remove all associated boundaries.`)) return;

    try {
      await api.delete(`/api/organizer/zones/${zoneId}`);
      toast(`Zone "${zoneName}" deleted successfully`, "success");
      fetchZonesAndLevels();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    // Strict QA validation
    const newErrors = {};
    if (!formData.name.trim()) {
      newErrors.name = "Zone name is required";
    }

    const opCap = formData.operating_capacity !== "" && formData.operating_capacity !== null ? parseInt(formData.operating_capacity, 10) : null;
    const capLimit = formData.capacity_limit !== "" && formData.capacity_limit !== null ? parseInt(formData.capacity_limit, 10) : null;

    if (opCap !== null && (isNaN(opCap) || opCap < 0)) {
      newErrors.operating_capacity = "Operating capacity cannot be negative";
    }

    if (capLimit !== null && (isNaN(capLimit) || capLimit < 0)) {
      newErrors.capacity_limit = "Fire / Legal Max capacity cannot be negative";
    }

    if (opCap !== null && capLimit !== null && opCap > 0 && capLimit > 0 && opCap > capLimit) {
      newErrors.operating_capacity = `Operating capacity cannot exceed Fire / Legal Max (${capLimit})`;
    }

    const adv = parseFloat(formData.advisory_threshold);
    const warn = parseFloat(formData.warning_threshold);
    const crit = parseFloat(formData.critical_threshold);

    if (adv >= warn || warn >= crit) {
      newErrors.thresholds = "Alert thresholds must be ordered: Advisory < Warning < Critical";
    }

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      const firstError = Object.values(newErrors)[0];
      toast(firstError, "warning");
      return; // Do NOT submit and do NOT close modal
    }

    try {
      const payload = {
        ...formData,
        name: formData.name.trim(),
        code: formData.code.trim() || formData.name.trim().slice(0, 8).toUpperCase(),
        capacity_limit: capLimit,
        operating_capacity: opCap,
        level_id: formData.level_id || null,
        advisory_threshold: adv,
        warning_threshold: warn,
        critical_threshold: crit,
      };

      if (editingZone) {
        await api.put(`/api/organizer/zones/${editingZone.id}`, payload);
        toast("Zone updated successfully", "success");
      } else {
        await api.post("/api/organizer/zones", {
          ...payload,
          event_id: selectedEventId,
        });
        toast("Zone created successfully", "success");
      }
      setIsModalOpen(false);
      fetchZonesAndLevels();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  return (
    <div className="fade-in">
      <div className="page-header">
        <div>
          <h1>Zone Capacity & Threshold Editor</h1>
          <p style={{ color: "var(--text-muted)", marginTop: "4px" }}>
            Configure spatial zones, safety thresholds, operational statuses, and floor levels.
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
          <button className="btn btn-primary" onClick={handleOpenCreate}>
            <LuPlus size={16} /> Add Zone
          </button>
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div style={{ padding: "40px", textAlign: "center" }}>
            <div className="spinner"></div>
          </div>
        ) : zones.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon"><LuMap /></div>
            <div className="empty-state-title">No zones defined</div>
            <div className="empty-state-text">
              Create spatial zones to track crowd density and configure automated safety thresholds.
            </div>
            <button className="btn btn-primary" style={{ marginTop: "16px" }} onClick={handleOpenCreate}>
              <LuPlus size={16} /> Create Zone
            </button>
          </div>
        ) : (
          <div className="table-container" style={{ overflowX: "auto", width: "100%", borderRadius: "var(--radius-lg)", border: "1px solid var(--border-default)" }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th style={{ minWidth: "170px" }}>Zone / Code</th>
                  <th style={{ minWidth: "130px" }}>Floor Level</th>
                  <th style={{ minWidth: "160px" }}>Capacity Limits</th>
                  <th style={{ minWidth: "190px" }}>Thresholds</th>
                  <th style={{ minWidth: "180px" }}>Operational Status</th>
                  <th style={{ minWidth: "130px" }}>Monitoring</th>
                  <th style={{ minWidth: "100px", textAlign: "right" }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {zones.map(zone => {
                  const levelMatch = levels.find(l => l.id === zone.level_id);
                  const statusObj = OPERATIONAL_STATUSES.find(s => s.value === zone.operational_status) || OPERATIONAL_STATUSES[0];

                  return (
                    <tr key={zone.id}>
                      <td>
                        <div style={{ fontWeight: "700", color: "var(--text-primary)" }}>{zone.name}</div>
                        <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "2px" }}>
                          Code: {zone.code || 'N/A'}
                        </div>
                      </td>
                      <td>
                        <span style={{ fontSize: "0.85rem", color: "var(--text-secondary)" }}>
                          {levelMatch ? (levelMatch.short_code || levelMatch.name) : "Main Level"}
                        </span>
                      </td>
                      <td>
                        <div style={{ fontSize: "0.85rem", display: "flex", alignItems: "baseline", gap: "4px" }}>
                          <span style={{ color: "var(--warning)", fontWeight: "600" }}>
                            {zone.operating_capacity || 'N/A'}
                          </span>
                          <span style={{ color: "var(--text-muted)", fontSize: "0.75rem" }}>
                            / {zone.capacity_limit || '∞'} max
                          </span>
                        </div>
                      </td>
                      <td>
                        <div style={{ display: "flex", gap: "6px", fontSize: "0.75rem", alignItems: "center" }}>
                          <span style={{ padding: "3px 8px", borderRadius: "4px", backgroundColor: "rgba(16, 185, 129, 0.15)", color: "#10B981", fontWeight: "600" }} title="Advisory">
                            {Math.round((zone.advisory_threshold ?? 0.70) * 100)}%
                          </span>
                          <span style={{ padding: "3px 8px", borderRadius: "4px", backgroundColor: "rgba(245, 158, 11, 0.15)", color: "#F59E0B", fontWeight: "600" }} title="Warning">
                            {Math.round((zone.warning_threshold ?? 0.85) * 100)}%
                          </span>
                          <span style={{ padding: "3px 8px", borderRadius: "4px", backgroundColor: "rgba(239, 68, 68, 0.15)", color: "#EF4444", fontWeight: "600" }} title="Critical">
                            {Math.round((zone.critical_threshold ?? 0.95) * 100)}%
                          </span>
                        </div>
                      </td>
                      <td>
                        <span 
                          style={{ 
                            padding: "4px 10px", 
                            borderRadius: "12px", 
                            fontSize: "0.75rem", 
                            fontWeight: "600",
                            backgroundColor: `${statusObj.color}20`,
                            color: statusObj.color,
                            border: `1px solid ${statusObj.color}40`,
                            display: "inline-block",
                            whiteSpace: "nowrap"
                          }}
                        >
                          {statusObj.label}
                        </span>
                      </td>
                      <td>
                        {zone.is_crowd_monitored ? (
                          <span className="badge info">Monitored</span>
                        ) : (
                          <span className="badge" style={{ backgroundColor: "var(--bg-elevated)", color: "var(--text-muted)" }}>Disabled</span>
                        )}
                      </td>
                      <td>
                        <div style={{ display: "flex", gap: "8px", justifyContent: "flex-end" }}>
                          <button className="btn btn-ghost btn-sm" onClick={() => handleOpenEdit(zone)} title="Edit Zone">
                            <LuPencil size={14} />
                          </button>
                          <button 
                            className="btn btn-ghost btn-sm" 
                            onClick={() => handleDeleteZone(zone.id, zone.name)} 
                            style={{ color: "var(--error)" }}
                            title="Delete Zone"
                          >
                            <LuTrash2 size={14} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* CREATE / EDIT ZONE MODAL */}
      {isModalOpen && (
        <div className="modal-overlay" onClick={() => setIsModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "580px", width: "100%" }}>
            <div className="modal-header">
              <h3>{editingZone ? `Edit "${editingZone.name}"` : "Create New Zone"}</h3>
              <button className="btn btn-ghost" onClick={() => setIsModalOpen(false)} style={{ fontSize: "1.2rem", padding: "4px 8px" }}>
                <LuX />
              </button>
            </div>
            
            <form onSubmit={handleSubmit}>
              <div className="modal-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                
                {/* Zone Name & Code */}
                <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: "12px" }}>
                  <div className="form-group">
                    <label className="form-label">Zone Name *</label>
                    <input 
                      type="text" 
                      className={`form-input ${errors.name ? "error" : ""}`} 
                      placeholder="e.g. North Concourse"
                      value={formData.name}
                      onChange={e => {
                        setFormData({...formData, name: e.target.value});
                        if (errors.name) setErrors(prev => ({ ...prev, name: null }));
                      }}
                      required 
                    />
                    {errors.name && <p className="form-error">{errors.name}</p>}
                  </div>
                  <div className="form-group">
                    <label className="form-label">Code</label>
                    <input 
                      type="text" 
                      className="form-input" 
                      placeholder="e.g. NC-1"
                      value={formData.code}
                      onChange={e => setFormData({...formData, code: e.target.value})}
                    />
                  </div>
                </div>

                {/* Multi-floor Level Association */}
                {levels.length > 0 && (
                  <div className="form-group">
                    <label className="form-label">
                      <LuLayers size={14} style={{ display: "inline", marginRight: "4px" }} />
                      Floor Level
                    </label>
                    <select
                      className="form-select"
                      value={formData.level_id}
                      onChange={e => setFormData({...formData, level_id: e.target.value})}
                    >
                      <option value="">-- No Level Associated (Default) --</option>
                      {levels.map(lvl => (
                        <option key={lvl.id} value={lvl.id}>
                          {lvl.name} ({lvl.short_code || `Level ${lvl.level_index}`})
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {/* Capacities */}
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                  <div className="form-group">
                    <label className="form-label">Operating Capacity (Target)</label>
                    <input 
                      type="number" 
                      min="0"
                      step="1"
                      className={`form-input ${errors.operating_capacity ? "error" : ""}`} 
                      placeholder="e.g. 500"
                      value={formData.operating_capacity}
                      onKeyDown={(e) => {
                        if (e.key === "-" || e.key === "e" || e.key === "+") e.preventDefault();
                      }}
                      onChange={e => {
                        const val = e.target.value;
                        if (val === "" || parseInt(val, 10) >= 0) {
                          setFormData({...formData, operating_capacity: val});
                          if (errors.operating_capacity) setErrors(prev => ({ ...prev, operating_capacity: null }));
                        }
                      }}
                    />
                    {errors.operating_capacity && <p className="form-error">{errors.operating_capacity}</p>}
                  </div>
                  <div className="form-group">
                    <label className="form-label">Fire / Legal Max Capacity</label>
                    <input 
                      type="number" 
                      min="0"
                      step="1"
                      className={`form-input ${errors.capacity_limit ? "error" : ""}`} 
                      placeholder="e.g. 600"
                      value={formData.capacity_limit}
                      onKeyDown={(e) => {
                        if (e.key === "-" || e.key === "e" || e.key === "+") e.preventDefault();
                      }}
                      onChange={e => {
                        const val = e.target.value;
                        if (val === "" || parseInt(val, 10) >= 0) {
                          setFormData({...formData, capacity_limit: val});
                          if (errors.capacity_limit) setErrors(prev => ({ ...prev, capacity_limit: null }));
                        }
                      }}
                    />
                    {errors.capacity_limit && <p className="form-error">{errors.capacity_limit}</p>}
                  </div>
                </div>

                {/* Safety Threshold Sliders */}
                <div style={{ background: "var(--bg-secondary)", padding: "14px", borderRadius: "8px", border: "1px solid var(--border-default)" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "6px", marginBottom: "12px", fontSize: "0.85rem", fontWeight: "700" }}>
                    <LuSlidersHorizontal size={16} /> Automated Alert Thresholds (% of Operating Capacity)
                  </div>

                  <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                    <div>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.8rem", marginBottom: "4px" }}>
                        <span style={{ color: "#10B981" }}>Advisory Notice:</span>
                        <strong>{Math.round(formData.advisory_threshold * 100)}%</strong>
                      </div>
                      <input 
                        type="range" 
                        min="0.10" 
                        max="0.85" 
                        step="0.05"
                        style={{ width: "100%", accentColor: "#10B981" }}
                        value={formData.advisory_threshold}
                        onChange={e => handleAdvisoryChange(e.target.value)}
                      />
                    </div>

                    <div>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.8rem", marginBottom: "4px" }}>
                        <span style={{ color: "#F59E0B" }}>Warning Alert:</span>
                        <strong>{Math.round(formData.warning_threshold * 100)}%</strong>
                      </div>
                      <input 
                        type="range" 
                        min="0.20" 
                        max="0.95" 
                        step="0.05"
                        style={{ width: "100%", accentColor: "#F59E0B" }}
                        value={formData.warning_threshold}
                        onChange={e => handleWarningChange(e.target.value)}
                      />
                    </div>

                    <div>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.8rem", marginBottom: "4px" }}>
                        <span style={{ color: "#EF4444" }}>Critical Evac / Lockdown:</span>
                        <strong>{Math.round(formData.critical_threshold * 100)}%</strong>
                      </div>
                      <input 
                        type="range" 
                        min="0.30" 
                        max="1.00" 
                        step="0.05"
                        style={{ width: "100%", accentColor: "#EF4444" }}
                        value={formData.critical_threshold}
                        onChange={e => handleCriticalChange(e.target.value)}
                      />
                    </div>
                    {errors.thresholds && <p className="form-error">{errors.thresholds}</p>}
                  </div>
                </div>

                {/* Zone Status Override Dropdown */}
                <div className="form-group">
                  <label className="form-label">
                    <LuShieldAlert size={14} style={{ display: "inline", marginRight: "4px" }} />
                    Zone Operational Status Override
                  </label>
                  <select
                    className="form-select"
                    value={formData.operational_status}
                    onChange={e => setFormData({...formData, operational_status: e.target.value})}
                  >
                    {OPERATIONAL_STATUSES.map(st => (
                      <option key={st.value} value={st.value}>
                        {st.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label style={{ display: "flex", alignItems: "center", gap: "8px", cursor: "pointer", fontSize: "0.85rem" }}>
                    <input 
                      type="checkbox" 
                      checked={formData.is_crowd_monitored}
                      onChange={e => setFormData({...formData, is_crowd_monitored: e.target.checked})}
                    />
                    Enable real-time BLE crowd telemetry and camera snapshots for this zone
                  </label>
                </div>
              </div>

              <div className="modal-footer">
                <button type="button" className="btn btn-secondary" onClick={() => setIsModalOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary">{editingZone ? "Save Changes" : "Create Zone"}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
