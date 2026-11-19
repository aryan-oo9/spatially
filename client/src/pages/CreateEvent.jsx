import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useToast } from "../components/Toast";
import { api } from "../utils/api";
import { getMinDate } from "../utils/validators";
import { LuPlus, LuX, LuLoader, LuBuilding, LuLayers } from "react-icons/lu";
import VenueMap from "../components/VenueMap";

export default function CreateEvent() {
  const toast = useToast();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);
  const [zoneInput, setZoneInput] = useState("");
  const [zoneFloorId, setZoneFloorId] = useState("");
  const [venues, setVenues] = useState([]);
  const [selectedVenue, setSelectedVenue] = useState(null);
  const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

  const [form, setForm] = useState({
    name: "",
    venue: "",
    venue_id: "",
    timezone: browserTz,
    event_date: "",
    start_time: "",
    end_time: "",
    description: "",
    capacity: "",
    ticket_price: "",
    location_address: "",
    organizer_name: "",
    zones: [],
  });
  const [errors, setErrors] = useState({});

  const [showModal, setShowModal] = useState(false);
  const [showMap, setShowMap] = useState(false);

  useEffect(() => {
    api.get("/api/venues")
      .then((data) => {
        const vList = data.venues || [];
        setVenues(vList);
        if (vList.length > 0 && !form.venue_id) {
          const first = vList[0];
          setForm((prev) => ({
            ...prev,
            venue_id: first.id,
            venue: first.name,
            location_address: first.address || prev.location_address,
            timezone: first.timezone || prev.timezone,
            capacity: first.default_capacity ? String(first.default_capacity) : prev.capacity,
          }));
          setSelectedVenue(first);
        }
      })
      .catch(() => {
        // Venues fetch fallback
      });
  }, []);

  const updateField = (field, value) => {
    setForm((prev) => ({ ...prev, [field]: value }));
    setErrors((prev) => ({ ...prev, [field]: null }));
  };

  const handleVenueSelect = (venueId) => {
    const v = venues.find((item) => item.id === venueId);
    if (v) {
      setForm((prev) => ({
        ...prev,
        venue_id: v.id,
        venue: v.name,
        location_address: v.address || prev.location_address,
        timezone: v.timezone || prev.timezone,
        capacity: v.default_capacity ? String(v.default_capacity) : prev.capacity,
      }));
      setSelectedVenue(v);
      if (v.levels && v.levels.length > 0) {
        setZoneFloorId(v.levels[0].id);
      }
      setErrors((prev) => ({ ...prev, venue_id: null, venue: null }));
    } else {
      setSelectedVenue(null);
      setZoneFloorId("");
      setForm((prev) => ({ ...prev, venue_id: venueId }));
    }
  };

  const addZone = () => {
    const name = zoneInput.trim();
    if (!name) return;
    const exists = form.zones.some((z) => {
      const zName = typeof z === "string" ? z : z.name;
      return zName.toLowerCase() === name.toLowerCase();
    });
    if (exists) {
      toast("Zone with this name already added", "warning");
      return;
    }

    const levels = selectedVenue?.levels || [];
    const targetLvl = levels.find((l) => l.id === zoneFloorId) || levels[0];
    const newZone = {
      name,
      level_id: targetLvl?.id || null,
      floor_level: targetLvl?.level_index !== undefined ? targetLvl.level_index + 1 : 1,
      short_code: targetLvl?.short_code || "G",
      floor_name: targetLvl?.name || "Base Floor",
    };

    setForm((prev) => ({ ...prev, zones: [...prev.zones, newZone] }));
    setZoneInput("");
  };

  const changeZoneFloor = (index, targetLevelId) => {
    const levels = selectedVenue?.levels || [];
    const targetLvl = levels.find((l) => l.id === targetLevelId);
    setForm((prev) => {
      const updated = [...prev.zones];
      const z = updated[index];
      const zName = typeof z === "string" ? z : z.name;
      updated[index] = {
        name: zName,
        level_id: targetLevelId,
        floor_level: targetLvl?.level_index !== undefined ? targetLvl.level_index + 1 : 1,
        short_code: targetLvl?.short_code || "G",
        floor_name: targetLvl?.name || "Floor",
      };
      return { ...prev, zones: updated };
    });
  };

  const removeZone = (zoneToRemove) => {
    const targetName = typeof zoneToRemove === "string" ? zoneToRemove : zoneToRemove.name;
    setForm((prev) => ({
      ...prev,
      zones: prev.zones.filter((z) => {
        const name = typeof z === "string" ? z : z.name;
        return name !== targetName;
      }),
    }));
  };

  const getMinStartTime = () => {
    if (!form.event_date) return "";
    const selectedDate = new Date(form.event_date);
    const now = new Date();
    if (selectedDate.toDateString() === now.toDateString()) {
      now.setMinutes(now.getMinutes() + 2);
      return `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
    }
    return "";
  };

  const getMinEndTime = () => {
    if (form.start_time) {
      const [h, m] = form.start_time.split(":").map(Number);
      const minEnd = new Date();
      minEnd.setHours(h, m + 15, 0, 0);
      return `${String(minEnd.getHours()).padStart(2, "0")}:${String(minEnd.getMinutes()).padStart(2, "0")}`;
    }
    return "";
  };

  const validate = () => {
    const newErrors = {};
    if (!form.name.trim()) newErrors.name = "Event name is required";
    if (!form.organizer_name.trim()) newErrors.organizer_name = "Organizer name is required";
    if (!form.venue_id) newErrors.venue_id = "Please select a registered venue";
    if (!form.venue.trim()) newErrors.venue = "Venue name is required";
    if (!form.event_date) newErrors.event_date = "Event date is required";
    if (form.event_date && form.event_date < getMinDate()) {
      newErrors.event_date = "Event date cannot be in the past";
    }

    if (form.ticket_price !== "" && form.ticket_price !== null && parseInt(form.ticket_price, 10) < 0) {
      newErrors.ticket_price = "Ticket price cannot be negative";
    }

    if (form.capacity !== "" && form.capacity !== null && parseInt(form.capacity, 10) < 0) {
      newErrors.capacity = "Maximum capacity cannot be negative";
    }

    // Mandatory start_time and end_time validation
    if (!form.start_time) {
      newErrors.start_time = "Start time is mandatory";
    } else {
      const selectedDate = form.event_date ? new Date(form.event_date) : null;
      const now = new Date();
      if (selectedDate && selectedDate.toDateString() === now.toDateString()) {
        const [startH, startM] = form.start_time.split(":").map(Number);
        const startMinutes = startH * 60 + startM;
        const nowMinutes = now.getHours() * 60 + now.getMinutes();
        if (startMinutes < nowMinutes) {
          newErrors.start_time = "Start time cannot be in the past";
        }
      }
    }

    if (!form.end_time) {
      newErrors.end_time = "End time is mandatory";
    } else if (form.start_time) {
      const [startH, startM] = form.start_time.split(":").map(Number);
      const [endH, endM] = form.end_time.split(":").map(Number);
      const startMinutes = startH * 60 + startM;
      const endMinutes = endH * 60 + endM;

      if (endMinutes <= startMinutes) {
        newErrors.end_time = "End time must be after start time";
      } else if (endMinutes < startMinutes + 15) {
        newErrors.end_time = "Event duration must be at least 15 minutes";
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleInitialSubmit = (e) => {
    e.preventDefault();
    if (!validate()) return;
    
    if (form.zones.length > 0) {
      setShowModal(true);
    } else {
      createEvent(null);
    }
  };

  const createEvent = async (customLayout = null) => {
    setSubmitting(true);
    try {
      let finalZones = form.zones.map((z) => (typeof z === "string" ? { name: z } : z));
      if (customLayout && customLayout.length > 0) {
        finalZones = customLayout.map((z) => ({
          name: z.name || z.zone,
          level_id: z.level_id || null,
          floor_level: z.floor_level || 1,
        }));
      }

      const payload = {
        ...form,
        zones: finalZones,
        capacity: form.capacity ? parseInt(form.capacity, 10) : 0,
        ticket_price: form.ticket_price ? parseInt(form.ticket_price, 10) : 0,
        event_date: form.event_date + "T00:00:00Z",
        venue_id: form.venue_id || null,
      };
      
      const res = await api.post("/api/events/", payload);
      const newEventId = res.event.id;

      if (customLayout) {
        await api.post(`/api/venue-map/${newEventId}/layout`, { layout: customLayout });
      }

      toast("Event created successfully!", "success");
      navigate(`/organizer/events/${newEventId}`);
    } catch (err) {
      toast(err.message || "Failed to create event", "error");
    } finally {
      setSubmitting(false);
      setShowModal(false);
      setShowMap(false);
    }
  };

  const handleAutoSetup = () => {
    setShowModal(false);
    createEvent(null);
  };

  const handleManualSetup = () => {
    setShowModal(false);
    setShowMap(true);
  };

  if (showMap) {
    return (
      <div className="fade-in" style={{ maxWidth: "900px", margin: "0 auto" }}>
        <div className="page-header">
          <h1>Finalize Zone Layout</h1>
        </div>
        <p style={{ color: "var(--text-secondary)", marginBottom: "20px" }}>
          You have chosen to manually size your zones. Once you click "Save Layout", this layout will be saved for this event.
        </p>
        
        <div className="card">
          <VenueMap
             eventId={null}
             venueLevels={selectedVenue?.levels || []}
             zones={form.zones}
             mode="create-event"
             onExitEditMode={(layout) => {
               if (layout) createEvent(layout);
               else setShowMap(false);
             }}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="fade-in" style={{ maxWidth: "900px", margin: "0 auto" }}>
      <div className="page-header">
        <h1>Create New Event</h1>
      </div>

      <form onSubmit={handleInitialSubmit} className="create-event-form" noValidate>
        <div className="card" style={{ marginBottom: "20px" }}>
          <h3 className="card-title" style={{ marginBottom: "20px" }}>Event Details</h3>

          <div className="form-group">
            <label className="form-label" htmlFor="event-name">Event Name *</label>
            <input id="event-name" type="text" className={`form-input ${errors.name ? "error" : ""}`} placeholder="Enter Event Name" value={form.name} onChange={(e) => updateField("name", e.target.value)} />
            {errors.name && <p className="form-error">{errors.name}</p>}
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="organizer-name">Organizer Name *</label>
            <input id="organizer-name" type="text" className={`form-input ${errors.organizer_name ? "error" : ""}`} placeholder="Your Name or Organization" value={form.organizer_name} onChange={(e) => updateField("organizer_name", e.target.value)} />
            {errors.organizer_name && <p className="form-error">{errors.organizer_name}</p>}
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="event-desc">Description</label>
            <textarea id="event-desc" className="form-textarea" placeholder="Describe the event, its theme, and what attendees can expect..." value={form.description} onChange={(e) => updateField("description", e.target.value)} />
          </div>

          {/* Venue Binding Dropdown & Address */}
          <div className="form-row">
            <div className="form-group">
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
                <label className="form-label" htmlFor="venue-select" style={{ marginBottom: 0 }}>
                  <LuBuilding size={14} style={{ display: "inline", marginRight: "4px" }} />
                  Select Venue *
                </label>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  onClick={() => navigate("/organizer/venues")}
                  style={{ fontSize: "0.78rem", color: "var(--primary-color, #10B981)", padding: "0 6px", height: "auto" }}
                >
                  + Add / Manage Venues
                </button>
              </div>
              <select
                id="venue-select"
                className={`form-select ${errors.venue_id ? "error" : ""}`}
                value={form.venue_id || ""}
                onChange={(e) => handleVenueSelect(e.target.value)}
              >
                <option value="">-- Choose Registered Venue --</option>
                {venues.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name} ({v.floor_count || v.levels?.length || 1} Floor{v.floor_count === 1 ? "" : "s"}{v.address ? ` • ${v.address}` : ""})
                  </option>
                ))}
              </select>
              {errors.venue_id && <p className="form-error">{errors.venue_id}</p>}
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="event-venue">Venue Name *</label>
              <input 
                id="event-venue" 
                type="text" 
                className={`form-input ${errors.venue ? "error" : ""}`} 
                placeholder="Convention Center Hall A" 
                value={form.venue} 
                onChange={(e) => updateField("venue", e.target.value)} 
              />
              {errors.venue && <p className="form-error">{errors.venue}</p>}
            </div>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="event-address">Venue Address</label>
            <input id="event-address" type="text" className="form-input" placeholder="123 Main Street, City" value={form.location_address} onChange={(e) => updateField("location_address", e.target.value)} />
          </div>

          {/* Imported Venue Structure & Floors */}
          {selectedVenue && (
            <div
              style={{
                background: "var(--bg-secondary)",
                border: "1px solid var(--border-light)",
                padding: "12px 16px",
                borderRadius: "10px",
                marginTop: "12px",
              }}
            >
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px", flexWrap: "wrap", gap: "6px" }}>
                <div style={{ fontSize: "0.85rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "6px" }}>
                  <LuLayers style={{ color: "var(--primary-color, #10B981)" }} />
                  Imported Venue Architecture: {selectedVenue.name} ({selectedVenue.levels?.length || 1} Floor{selectedVenue.levels?.length === 1 ? "" : "s"})
                </div>
                <span className="badge badge-primary" style={{ textTransform: "capitalize", fontSize: "0.75rem" }}>
                  {selectedVenue.venue_type ? selectedVenue.venue_type.replace("_", " ") : "Multi Floor"}
                </span>
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                {(selectedVenue.levels || []).map((lvl) => (
                  <span
                    key={lvl.id || lvl.level_index}
                    style={{
                      background: "var(--bg-card)",
                      border: "1px solid var(--border-light)",
                      padding: "3px 8px",
                      borderRadius: "6px",
                      fontSize: "0.8rem",
                      display: "inline-flex",
                      alignItems: "center",
                      gap: "5px",
                    }}
                  >
                    <strong style={{ color: "var(--primary-color, #10B981)", fontFamily: "monospace" }}>
                      [{lvl.short_code || `L${lvl.level_index}`}]
                    </strong>
                    <span>{lvl.name}</span>
                  </span>
                ))}
              </div>
              <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", marginTop: "8px", marginBottom: 0 }}>
                ✓ Venue floors imported. Each floor has its own distinct spatial layout for the organizer dashboard and attendee app.
              </p>
            </div>
          )}
        </div>

        {/* Schedule: Mandatory Date, Start Time & End Time */}
        <div className="card" style={{ marginBottom: "20px" }}>
          <h3 className="card-title" style={{ marginBottom: "20px" }}>Schedule (Mandatory)</h3>

          <div className="form-row">
            <div className="form-group">
              <label className="form-label" htmlFor="event-date">Event Date *</label>
              <input id="event-date" type="date" className={`form-input ${errors.event_date ? "error" : ""}`} min={getMinDate()} value={form.event_date} onChange={(e) => updateField("event_date", e.target.value)} />
              {errors.event_date && <p className="form-error">{errors.event_date}</p>}
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="event-tz">Event Timezone *</label>
              <select
                id="event-tz"
                className="form-select"
                value={form.timezone}
                onChange={(e) => updateField("timezone", e.target.value)}
              >
                <option value="UTC">UTC</option>
                <option value="America/New_York">America/New_York (Eastern)</option>
                <option value="America/Chicago">America/Chicago (Central)</option>
                <option value="America/Denver">America/Denver (Mountain)</option>
                <option value="America/Los_Angeles">America/Los_Angeles (Pacific)</option>
                <option value="Europe/London">Europe/London (GMT/BST)</option>
                <option value="Europe/Paris">Europe/Paris (CET)</option>
                <option value="Asia/Kolkata">Asia/Kolkata (IST)</option>
                <option value="Asia/Tokyo">Asia/Tokyo (JST)</option>
                <option value="Asia/Singapore">Asia/Singapore (SGT)</option>
                <option value="Australia/Sydney">Australia/Sydney (AEST)</option>
                {form.timezone && !["UTC", "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "Europe/London", "Europe/Paris", "Asia/Kolkata", "Asia/Tokyo", "Asia/Singapore", "Australia/Sydney"].includes(form.timezone) && (
                  <option value={form.timezone}>{form.timezone} (Local)</option>
                )}
              </select>
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label className="form-label" htmlFor="event-start">Start Time *</label>
              <input id="event-start" type="time" className={`form-input ${errors.start_time ? "error" : ""}`} min={getMinStartTime()} value={form.start_time} onChange={(e) => updateField("start_time", e.target.value)} />
              {errors.start_time && <p className="form-error">{errors.start_time}</p>}
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="event-end">End Time *</label>
              <input id="event-end" type="time" className={`form-input ${errors.end_time ? "error" : ""}`} min={getMinEndTime()} value={form.end_time} onChange={(e) => updateField("end_time", e.target.value)} />
              {errors.end_time && <p className="form-error">{errors.end_time}</p>}
            </div>
          </div>
        </div>

        {/* Ticketing & Pricing */}
        <div className="card" style={{ marginBottom: "20px" }}>
          <h3 className="card-title" style={{ marginBottom: "8px" }}>Ticket Price & Admission</h3>
          <p style={{ color: "var(--text-secondary)", fontSize: "13px", marginBottom: "16px" }}>
            Set the admission price in Points. Attendees will redeem their gamified quest points or promotional coupons to purchase tickets. Enter 0 for free admission.
          </p>

          <div className="form-group">
            <label className="form-label" htmlFor="ticket-price">Ticket Price (Points) *</label>
            <input
              id="ticket-price"
              type="number"
              min="0"
              step="1"
              className={`form-input ${errors.ticket_price ? "error" : ""}`}
              placeholder="e.g. 100 (0 for free)"
              value={form.ticket_price}
              onKeyDown={(e) => {
                if (e.key === "-" || e.key === "e" || e.key === "+") e.preventDefault();
              }}
              onChange={(e) => {
                const val = e.target.value;
                if (val === "" || parseInt(val, 10) >= 0) {
                  updateField("ticket_price", val);
                }
              }}
            />
            {errors.ticket_price && <p className="form-error">{errors.ticket_price}</p>}
          </div>
        </div>

        <div className="card" style={{ marginBottom: "20px" }}>
          <h3 className="card-title" style={{ marginBottom: "20px" }}>Capacity & Zones</h3>

          <div className="form-group">
            <label className="form-label" htmlFor="event-capacity">Maximum Capacity</label>
            <input 
              id="event-capacity" 
              type="number" 
              className={`form-input ${errors.capacity ? "error" : ""}`} 
              placeholder="0 = Unlimited" 
              min="0" 
              step="1"
              value={form.capacity} 
              onKeyDown={(e) => {
                if (e.key === "-" || e.key === "e" || e.key === "+") e.preventDefault();
              }}
              onChange={(e) => {
                const val = e.target.value;
                if (val === "" || parseInt(val, 10) >= 0) {
                  updateField("capacity", val);
                }
              }} 
            />
            {errors.capacity && <p className="form-error">{errors.capacity}</p>}
          </div>

          <div className="form-group">
            <label className="form-label">Event Zones & Floor Allocation</label>
            <p style={{ fontSize: "0.82rem", color: "var(--text-muted)", marginBottom: "8px" }}>
              Add functional zones and assign each zone to its physical floor.
            </p>
            <div className="zones-input-row" style={{ display: "flex", gap: "8px", alignItems: "center", flexWrap: "wrap" }}>
              <input
                type="text"
                className="form-input"
                placeholder="Zone name (e.g. Main Auditorium, Food Court)..."
                value={zoneInput}
                onChange={(e) => setZoneInput(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); addZone(); } }}
                style={{ flex: 1, minWidth: "220px" }}
              />
              {selectedVenue?.levels && selectedVenue.levels.length > 0 && (
                <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                  <span style={{ fontSize: "0.8rem", color: "var(--text-muted)", whiteSpace: "nowrap" }}>Floor:</span>
                  <select
                    className="form-select"
                    value={zoneFloorId}
                    onChange={(e) => setZoneFloorId(e.target.value)}
                    style={{ minWidth: "160px" }}
                  >
                    {selectedVenue.levels.map((lvl) => (
                      <option key={lvl.id} value={lvl.id}>
                        [{lvl.short_code || `L${lvl.level_index}`}] {lvl.name}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              <button type="button" className="btn btn-secondary" onClick={addZone} style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <LuPlus size={16} /> Add Zone
              </button>
            </div>
            {form.zones.length > 0 && (
              <div className="zones-list" style={{ display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "14px" }}>
                {form.zones.map((zone, idx) => {
                  const zName = typeof zone === "string" ? zone : zone.name;
                  const zLevelId = typeof zone === "object" ? zone.level_id : null;
                  const zLvl = (selectedVenue?.levels || []).find((l) => l.id === zLevelId) || selectedVenue?.levels?.[0];
                  return (
                    <span key={idx} className="zone-chip" style={{ display: "inline-flex", alignItems: "center", gap: "8px", padding: "6px 12px" }}>
                      <strong style={{ color: "var(--text-primary)" }}>{zName}</strong>
                      {selectedVenue?.levels && selectedVenue.levels.length > 1 ? (
                        <div style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
                          <span style={{ fontSize: "0.72rem", color: "var(--text-muted)" }}>on</span>
                          <select
                            value={zLevelId || selectedVenue.levels[0]?.id}
                            onChange={(e) => changeZoneFloor(idx, e.target.value)}
                            style={{
                              fontSize: "0.75rem",
                              padding: "2px 6px",
                              borderRadius: "6px",
                              border: "1px solid var(--border-light)",
                              background: "var(--bg-secondary)",
                              color: "var(--primary-color, #10B981)",
                              fontWeight: "700",
                              cursor: "pointer",
                            }}
                          >
                            {selectedVenue.levels.map((lvl) => (
                              <option key={lvl.id} value={lvl.id}>
                                [{lvl.short_code || `L${lvl.level_index}`}] {lvl.name}
                              </option>
                            ))}
                          </select>
                        </div>
                      ) : (
                        <span className="badge badge-neutral" style={{ fontSize: "0.72rem" }}>
                          [{zLvl?.short_code || "G"}]
                        </span>
                      )}
                      <button type="button" onClick={() => removeZone(zone)} aria-label={`Remove ${zName} zone`} style={{ marginLeft: "4px" }}>
                        <LuX size={14} />
                      </button>
                    </span>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        <div style={{ display: "flex", gap: "12px" }}>
          <button type="submit" className="btn btn-primary btn-lg" disabled={submitting}>
            {submitting ? <><LuLoader style={{ animation: "spin 0.8s linear infinite" }} /> Creating...</> : "Create Event"}
          </button>
          <button type="button" className="btn btn-secondary btn-lg" onClick={() => navigate("/organizer/events")}>
            Cancel
          </button>
        </div>
      </form>

      {/* Setup Zones Modal */}
      {showModal && (
        <div className="modal-overlay fade-in" style={{ display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div className="modal" style={{ background: "var(--bg-elevated)", padding: "24px", borderRadius: "12px", maxWidth: "500px", width: "100%", border: "1px solid var(--border-light)" }}>
            <h2 style={{ marginBottom: "16px", color: "var(--text-primary)" }}>Setup Venue Zones</h2>
            <p style={{ color: "var(--text-secondary)", marginBottom: "24px", lineHeight: "1.5" }}>
              You have added zones to this event. How would you like them mapped out in the stadium? 
              <br /><br />
              <strong>Note: You can further refine spatial coordinates in the vector map editor.</strong>
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
              <button className="btn btn-primary btn-lg" onClick={handleAutoSetup}>
                Automatic (Divide Equally)
              </button>
              <button className="btn btn-secondary btn-lg" onClick={handleManualSetup}>
                Manually Edit Zones
              </button>
            </div>
            <button className="btn btn-ghost" style={{ marginTop: "16px", width: "100%" }} onClick={() => setShowModal(false)}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
