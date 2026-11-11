import { useState, useEffect } from "react";
import { api } from "../utils/api";
import { useToast } from "../components/Toast";
import {
  LuBuilding,
  LuPlus,
  LuPencil,
  LuTrash2,
  LuMapPin,
  LuLayers,
  LuClock,
  LuUsers,
  LuX,
  LuCheck,
  LuCopy,
} from "react-icons/lu";

const LEVEL_TYPES = [
  { value: "indoor_floor", label: "Indoor Floor" },
  { value: "outdoor_ground", label: "Outdoor / Ground" },
  { value: "mezzanine", label: "Mezzanine" },
  { value: "rooftop", label: "Rooftop" },
  { value: "parking", label: "Parking Level" },
];

export default function OrganizerVenues() {
  const toast = useToast();
  const [venues, setVenues] = useState([]);
  const [loading, setLoading] = useState(true);
  const [panelOpen, setPanelOpen] = useState(false);
  const [editingVenue, setEditingVenue] = useState(null);
  const [cloneSourceVenueId, setCloneSourceVenueId] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

  // Form state
  const [form, setForm] = useState({
    name: "",
    address: "",
    timezone: browserTz,
    venue_type: "multi_floor",
    default_capacity: "",
    floors: [
      {
        level_index: 0,
        name: "Ground Floor",
        short_code: "G",
        level_type: "indoor_floor",
        display_order: 0,
      },
    ],
  });

  const [errors, setErrors] = useState({});

  const fetchVenues = () => {
    setLoading(true);
    api.get("/api/venues")
      .then((data) => {
        setVenues(data.venues || []);
      })
      .catch((err) => {
        toast(err.message || "Failed to load venues", "error");
      })
      .finally(() => {
        setLoading(false);
      });
  };

  useEffect(() => {
    fetchVenues();
  }, []);

  const openCreatePanel = () => {
    setEditingVenue(null);
    setCloneSourceVenueId("");
    setForm({
      name: "",
      address: "",
      timezone: browserTz,
      venue_type: "multi_floor",
      default_capacity: "",
      floors: [
        {
          level_index: 0,
          name: "Ground Floor",
          short_code: "G",
          level_type: "indoor_floor",
          display_order: 0,
        },
      ],
    });
    setErrors({});
    setPanelOpen(true);
  };

  const openEditPanel = (venue) => {
    setEditingVenue(venue);
    setCloneSourceVenueId("");
    const existingFloors = (venue.levels || []).map((lvl, idx) => ({
      id: lvl.id,
      level_index: lvl.level_index ?? idx,
      name: lvl.name || `Floor ${idx}`,
      short_code: lvl.short_code || `L${idx}`,
      level_type: lvl.level_type || "indoor_floor",
      display_order: lvl.display_order ?? idx,
    }));

    setForm({
      name: venue.name || "",
      address: venue.address || "",
      timezone: venue.timezone || browserTz,
      venue_type: venue.venue_type || "multi_floor",
      default_capacity: venue.default_capacity ? String(venue.default_capacity) : "",
      floors: existingFloors.length > 0 ? existingFloors : [
        {
          level_index: 0,
          name: "Ground Floor",
          short_code: "G",
          level_type: "indoor_floor",
          display_order: 0,
        },
      ],
    });
    setErrors({});
    setPanelOpen(true);
  };

  // Duplicate an existing venue into the side panel
  const handleDuplicateVenue = (sourceVenue) => {
    setEditingVenue(null);
    setCloneSourceVenueId(sourceVenue.id);

    const clonedFloors = (sourceVenue.levels || []).map((lvl, idx) => ({
      level_index: lvl.level_index ?? idx,
      name: lvl.name || (idx === 0 ? "Ground Floor" : `Level ${idx}`),
      short_code: lvl.short_code || (idx === 0 ? "G" : `L${idx}`),
      level_type: lvl.level_type || "indoor_floor",
      display_order: idx,
    }));

    setForm({
      name: `${sourceVenue.name} (Copy)`,
      address: sourceVenue.address || "",
      timezone: sourceVenue.timezone || browserTz,
      venue_type: sourceVenue.venue_type || "multi_floor",
      default_capacity: sourceVenue.default_capacity ? String(sourceVenue.default_capacity) : "",
      floors: clonedFloors.length > 0 ? clonedFloors : [
        {
          level_index: 0,
          name: "Ground Floor",
          short_code: "G",
          level_type: "indoor_floor",
          display_order: 0,
        },
      ],
    });
    setErrors({});
    setPanelOpen(true);
    toast(`Copied venue & floor structure from "${sourceVenue.name}". Adjust details and save.`, "info");
  };

  // Selector inside side panel to clone from existing venue
  const handleCloneSelectChange = (sourceVenueId) => {
    setCloneSourceVenueId(sourceVenueId);
    if (!sourceVenueId) {
      // Reset to empty base
      setForm({
        name: "",
        address: "",
        timezone: browserTz,
        venue_type: "multi_floor",
        default_capacity: "",
        floors: [
          {
            level_index: 0,
            name: "Ground Floor",
            short_code: "G",
            level_type: "indoor_floor",
            display_order: 0,
          },
        ],
      });
      return;
    }

    const source = venues.find((v) => v.id === sourceVenueId);
    if (!source) return;

    const clonedFloors = (source.levels || []).map((lvl, idx) => ({
      level_index: lvl.level_index ?? idx,
      name: lvl.name || (idx === 0 ? "Ground Floor" : `Level ${idx}`),
      short_code: lvl.short_code || (idx === 0 ? "G" : `L${idx}`),
      level_type: lvl.level_type || "indoor_floor",
      display_order: idx,
    }));

    setForm({
      name: `${source.name} (Copy)`,
      address: source.address || "",
      timezone: source.timezone || browserTz,
      venue_type: source.venue_type || "multi_floor",
      default_capacity: source.default_capacity ? String(source.default_capacity) : "",
      floors: clonedFloors.length > 0 ? clonedFloors : [
        {
          level_index: 0,
          name: "Ground Floor",
          short_code: "G",
          level_type: "indoor_floor",
          display_order: 0,
        },
      ],
    });
    toast(`Imported all details and ${clonedFloors.length} floor layouts from "${source.name}".`, "success");
  };

  // Floor management handlers
  const setTotalFloorsCount = (count) => {
    const target = Math.max(1, Math.min(20, count));
    const currentFloors = [...form.floors];

    if (target > currentFloors.length) {
      for (let i = currentFloors.length; i < target; i++) {
        currentFloors.push({
          level_index: i,
          name: i === 0 ? "Ground Floor" : `Level ${i}`,
          short_code: i === 0 ? "G" : `L${i}`,
          level_type: "indoor_floor",
          display_order: i,
        });
      }
    } else if (target < currentFloors.length) {
      currentFloors.splice(target);
    }
    setForm((prev) => ({ ...prev, floors: currentFloors }));
  };

  const addFloor = () => {
    const nextIdx = form.floors.length;
    const newFloor = {
      level_index: nextIdx,
      name: `Level ${nextIdx}`,
      short_code: `L${nextIdx}`,
      level_type: "indoor_floor",
      display_order: nextIdx,
    };
    setForm((prev) => ({ ...prev, floors: [...prev.floors, newFloor] }));
  };

  const removeFloor = (indexToRemove) => {
    if (form.floors.length <= 1) {
      toast("Venue must contain at least a Base Floor (Level 0)", "warning");
      return;
    }
    const updated = form.floors
      .filter((_, idx) => idx !== indexToRemove)
      .map((f, newIdx) => ({
        ...f,
        level_index: newIdx,
        display_order: newIdx,
      }));
    setForm((prev) => ({ ...prev, floors: updated }));
  };

  const updateFloorField = (index, field, value) => {
    const updated = [...form.floors];
    updated[index] = { ...updated[index], [field]: value };
    setForm((prev) => ({ ...prev, floors: updated }));
  };

  const validate = () => {
    const newErrors = {};
    if (!form.name.trim()) newErrors.name = "Venue name is required";
    if (form.floors.length === 0) newErrors.floors = "At least one base floor is required";
    form.floors.forEach((f, idx) => {
      if (!f.name.trim()) {
        newErrors[`floor_${idx}_name`] = "Floor name cannot be blank";
      }
      if (!f.short_code.trim()) {
        newErrors[`floor_${idx}_code`] = "Code required";
      }
    });
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!validate()) return;

    setSubmitting(true);
    try {
      const payload = {
        name: form.name.trim(),
        address: form.address.trim(),
        timezone: form.timezone,
        venue_type: form.venue_type,
        default_capacity: form.default_capacity ? parseInt(form.default_capacity, 10) : 0,
        floors: form.floors.map((f, idx) => ({
          id: f.id || undefined,
          level_index: f.level_index !== undefined ? f.level_index : idx,
          name: f.name.trim(),
          short_code: f.short_code.trim().toUpperCase(),
          level_type: f.level_type || "indoor_floor",
          display_order: idx,
        })),
      };

      if (editingVenue) {
        await api.put(`/api/venues/${editingVenue.id}`, payload);
        toast("Venue and floor layouts updated successfully!", "success");
      } else {
        await api.post("/api/venues", payload);
        toast("Venue registered with configured floor layouts!", "success");
      }

      setPanelOpen(false);
      fetchVenues();
    } catch (err) {
      toast(err.message || "Failed to save venue", "error");
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteVenue = async (venue) => {
    if (!window.confirm(`Are you sure you want to delete "${venue.name}"? Linked events will be unassigned from this venue.`)) {
      return;
    }
    try {
      await api.delete(`/api/venues/${venue.id}`);
      toast(`Venue "${venue.name}" deleted`, "success");
      fetchVenues();
    } catch (err) {
      toast(err.message || "Failed to delete venue", "error");
    }
  };

  return (
    <div className="fade-in" style={{ maxWidth: "1200px", margin: "0 auto", paddingBottom: "40px" }}>
      {/* Page Header */}
      <div className="page-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <LuBuilding style={{ color: "var(--primary-color, #10B981)" }} />
            Venues & Floor Layouts
          </h1>
          <p style={{ color: "var(--text-muted)", marginTop: "6px", fontSize: "0.95rem" }}>
            Create reusable venue profiles with tailored floor structures. Each floor receives its own distinct spatial layout for both the organizer dashboard and the attendee mobile app.
          </p>
        </div>
        <button
          type="button"
          className="btn btn-primary"
          onClick={openCreatePanel}
          style={{ display: "flex", alignItems: "center", gap: "8px" }}
        >
          <LuPlus size={18} />
          <span>Add New Venue</span>
        </button>
      </div>

      {/* Venues Content */}
      {loading ? (
        <div style={{ display: "flex", justifyContent: "center", alignItems: "center", minHeight: "300px" }}>
          <div className="spinner"></div>
        </div>
      ) : venues.length === 0 ? (
        <div className="card" style={{ textAlign: "center", padding: "60px 20px" }}>
          <div style={{ fontSize: "3rem", color: "var(--text-muted)", marginBottom: "16px" }}>
            <LuBuilding />
          </div>
          <h3 style={{ marginBottom: "8px" }}>No Venues Added Yet</h3>
          <p style={{ color: "var(--text-muted)", maxWidth: "500px", margin: "0 auto 24px" }}>
            Add your physical venue here. Start with a Base Floor, then define how many floors exist to generate separate map layouts for your events.
          </p>
          <button type="button" className="btn btn-primary" onClick={openCreatePanel}>
            <LuPlus size={16} style={{ marginRight: "6px" }} /> Add Your First Venue
          </button>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(360px, 1fr))", gap: "20px" }}>
          {venues.map((venue) => {
            const levels = venue.levels || [];
            return (
              <div
                key={venue.id}
                className="card"
                style={{
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "space-between",
                  transition: "transform 0.15s ease, box-shadow 0.15s ease",
                  border: "1px solid var(--border-light)",
                }}
              >
                <div>
                  {/* Top Bar */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "12px" }}>
                    <div>
                      <h3 style={{ fontSize: "1.2rem", fontWeight: "700", marginBottom: "4px" }}>
                        {venue.name}
                      </h3>
                      <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--text-muted)", fontSize: "0.85rem" }}>
                        <LuMapPin size={14} style={{ flexShrink: 0 }} />
                        <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: "260px" }}>
                          {venue.address || "No address specified"}
                        </span>
                      </div>
                    </div>
                    <span className="badge badge-primary" style={{ textTransform: "capitalize", fontSize: "0.75rem" }}>
                      {venue.venue_type ? venue.venue_type.replace("_", " ") : "Multi Floor"}
                    </span>
                  </div>

                  {/* Stats Row */}
                  <div
                    style={{
                      display: "flex",
                      gap: "12px",
                      background: "var(--bg-secondary)",
                      padding: "10px 14px",
                      borderRadius: "8px",
                      marginBottom: "16px",
                      fontSize: "0.85rem",
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                      <LuLayers size={15} style={{ color: "var(--primary-color, #10B981)" }} />
                      <span><strong>{levels.length}</strong> Floor{levels.length === 1 ? "" : "s"}</span>
                    </div>
                    {venue.default_capacity > 0 && (
                      <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <LuUsers size={15} style={{ color: "#3B82F6" }} />
                        <span>Cap: <strong>{venue.default_capacity}</strong></span>
                      </div>
                    )}
                    <div style={{ display: "flex", alignItems: "center", gap: "6px", marginLeft: "auto" }}>
                      <LuClock size={14} style={{ color: "var(--text-muted)" }} />
                      <span style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>{venue.timezone || "UTC"}</span>
                    </div>
                  </div>

                  {/* Floor Breakdown Pills */}
                  <div style={{ marginBottom: "16px" }}>
                    <div style={{ fontSize: "0.8rem", fontWeight: "600", textTransform: "uppercase", letterSpacing: "0.5px", color: "var(--text-muted)", marginBottom: "8px" }}>
                      Configured Floor Layouts:
                    </div>
                    <div style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                      {levels.map((lvl) => (
                        <span
                          key={lvl.id || lvl.level_index}
                          style={{
                            background: "var(--bg-card)",
                            border: "1px solid var(--border-light)",
                            padding: "4px 8px",
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
                  </div>
                </div>

                {/* Card Actions */}
                <div style={{ display: "flex", gap: "8px", borderTop: "1px solid var(--border-light)", paddingTop: "12px", marginTop: "12px" }}>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => openEditPanel(venue)}
                    style={{ flex: 1, display: "flex", justifyContent: "center", alignItems: "center", gap: "6px" }}
                  >
                    <LuPencil size={14} /> Edit
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => handleDuplicateVenue(venue)}
                    title="Duplicate this venue with all its floors"
                    style={{ display: "flex", justifyContent: "center", alignItems: "center", gap: "6px" }}
                  >
                    <LuCopy size={14} /> Copy
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={() => handleDeleteVenue(venue)}
                    title="Delete Venue"
                    style={{ color: "var(--error, #EF4444)" }}
                  >
                    <LuTrash2 size={16} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Side Panel Drawer (Replaces modal) */}
      {panelOpen && (
        <>
          {/* Backdrop Overlay */}
          <div
            className="side-panel-overlay fade-in"
            onClick={() => setPanelOpen(false)}
            style={{
              position: "fixed",
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              background: "rgba(0, 0, 0, 0.65)",
              backdropFilter: "blur(3px)",
              zIndex: 1050,
            }}
          />

          {/* Sliding Side Panel Drawer */}
          <aside
            className="side-panel"
            role="dialog"
            aria-modal="true"
            style={{
              position: "fixed",
              top: 0,
              right: 0,
              bottom: 0,
              width: "100%",
              maxWidth: "580px",
              background: "var(--bg-card, #0f172a)",
              boxShadow: "-12px 0 35px rgba(0, 0, 0, 0.55)",
              borderLeft: "1px solid var(--border-light)",
              zIndex: 1060,
              display: "flex",
              flexDirection: "column",
              animation: "slideInRight 0.25s cubic-bezier(0.16, 1, 0.3, 1)",
            }}
          >
            {/* Side Panel Header */}
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "20px 24px",
                borderBottom: "1px solid var(--border-light)",
                background: "var(--bg-secondary)",
                flexShrink: 0,
              }}
            >
              <div>
                <h2 style={{ fontSize: "1.25rem", fontWeight: "700", display: "flex", alignItems: "center", gap: "10px", margin: 0 }}>
                  <LuBuilding style={{ color: "var(--primary-color, #10B981)" }} />
                  {editingVenue ? `Edit Venue: ${editingVenue.name}` : cloneSourceVenueId ? "Create Copy of Venue" : "Add New Physical Venue"}
                </h2>
                <p style={{ color: "var(--text-muted)", fontSize: "0.82rem", marginTop: "4px", marginBottom: 0 }}>
                  {editingVenue ? "Modify venue details and update floor configurations." : "Configure venue properties and customize separate layouts per floor."}
                </p>
              </div>
              <button
                type="button"
                className="btn btn-ghost btn-sm"
                onClick={() => setPanelOpen(false)}
                style={{ padding: "6px", borderRadius: "8px" }}
                aria-label="Close side panel"
              >
                <LuX size={20} />
              </button>
            </div>

            {/* Side Panel Scrollable Form Body */}
            <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 }}>
              <div style={{ flex: 1, overflowY: "auto", padding: "24px" }}>
                
                {/* Clone / Copy Existing Venue Selector (Visible when creating/duplicating) */}
                {venues.length > 0 && !editingVenue && (
                  <div
                    style={{
                      background: "rgba(16, 185, 129, 0.06)",
                      border: "1px dashed rgba(16, 185, 129, 0.35)",
                      borderRadius: "10px",
                      padding: "14px 16px",
                      marginBottom: "24px",
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "6px" }}>
                      <LuCopy size={16} style={{ color: "var(--primary-color, #10B981)" }} />
                      <strong style={{ fontSize: "0.9rem", color: "var(--text-primary)" }}>
                        Copy From An Existing Venue
                      </strong>
                    </div>
                    <p style={{ fontSize: "0.8rem", color: "var(--text-muted)", marginBottom: "10px" }}>
                      Select a venue to automatically copy its capacity, address, and all floor layouts:
                    </p>
                    <select
                      className="form-select form-select-sm"
                      value={cloneSourceVenueId}
                      onChange={(e) => handleCloneSelectChange(e.target.value)}
                      style={{ background: "var(--bg-card)" }}
                    >
                      <option value="">-- Start from scratch (Blank Template) --</option>
                      {venues.map((v) => (
                        <option key={v.id} value={v.id}>
                          Clone: {v.name} ({v.levels?.length || 1} Floor{v.levels?.length === 1 ? "" : "s"}{v.address ? ` • ${v.address}` : ""})
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {/* Section 1: Venue Information */}
                <div style={{ marginBottom: "28px" }}>
                  <h4 style={{ fontSize: "0.95rem", fontWeight: "700", marginBottom: "14px", color: "var(--text-primary)", display: "flex", alignItems: "center", gap: "8px" }}>
                    <span style={{ background: "var(--primary-color, #10B981)", color: "#fff", width: "20px", height: "20px", borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: "0.75rem" }}>1</span>
                    Venue Information
                  </h4>

                  <div className="form-group" style={{ marginBottom: "14px" }}>
                    <label className="form-label" htmlFor="v-name">Venue Name *</label>
                    <input
                      id="v-name"
                      type="text"
                      className={`form-input ${errors.name ? "error" : ""}`}
                      placeholder="e.g. Metro Convention Center & Arena"
                      value={form.name}
                      onChange={(e) => setForm({ ...form, name: e.target.value })}
                    />
                    {errors.name && <p className="form-error">{errors.name}</p>}
                  </div>

                  <div className="form-group" style={{ marginBottom: "14px" }}>
                    <label className="form-label" htmlFor="v-address">Physical Address</label>
                    <input
                      id="v-address"
                      type="text"
                      className="form-input"
                      placeholder="e.g. 100 Marina Boulevard, Sector 4"
                      value={form.address}
                      onChange={(e) => setForm({ ...form, address: e.target.value })}
                    />
                  </div>

                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "14px" }}>
                    <div className="form-group">
                      <label className="form-label" htmlFor="v-type">Venue Type</label>
                      <select
                        id="v-type"
                        className="form-select"
                        value={form.venue_type}
                        onChange={(e) => setForm({ ...form, venue_type: e.target.value })}
                      >
                        <option value="multi_floor">Multi-Floor Complex</option>
                        <option value="single_level">Single-Level Center</option>
                        <option value="outdoor">Outdoor Ground / Park</option>
                        <option value="hybrid">Hybrid Indoor / Outdoor</option>
                      </select>
                    </div>

                    <div className="form-group">
                      <label className="form-label" htmlFor="v-cap">Default Venue Capacity</label>
                      <input
                        id="v-cap"
                        type="number"
                        min="0"
                        className="form-input"
                        placeholder="e.g. 3500"
                        value={form.default_capacity}
                        onChange={(e) => setForm({ ...form, default_capacity: e.target.value })}
                      />
                    </div>
                  </div>
                </div>

                {/* Section 2: Floors & Levels Configuration */}
                <div style={{ borderTop: "1px solid var(--border-light)", paddingTop: "20px" }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "12px", flexWrap: "wrap", gap: "10px" }}>
                    <div>
                      <h4 style={{ fontSize: "0.95rem", fontWeight: "700", color: "var(--text-primary)", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}>
                        <span style={{ background: "var(--primary-color, #10B981)", color: "#fff", width: "20px", height: "20px", borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: "0.75rem" }}>2</span>
                        Architectural Floors & Levels
                      </h4>
                      <p style={{ color: "var(--text-muted)", fontSize: "0.8rem", marginTop: "3px", marginBottom: 0 }}>
                        Starts with a <strong>Base Floor</strong>. Set how many floors exist:
                      </p>
                    </div>

                    {/* Floor Counter Controller */}
                    <div style={{ display: "flex", alignItems: "center", gap: "8px", background: "var(--bg-secondary)", padding: "4px 8px", borderRadius: "8px", border: "1px solid var(--border-light)" }}>
                      <span style={{ fontSize: "0.8rem", color: "var(--text-muted)", fontWeight: "600" }}>Total Floors:</span>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        style={{ padding: "2px 8px" }}
                        disabled={form.floors.length <= 1}
                        onClick={() => setTotalFloorsCount(form.floors.length - 1)}
                      >
                        -
                      </button>
                      <strong style={{ minWidth: "20px", textAlign: "center", fontSize: "0.95rem" }}>
                        {form.floors.length}
                      </strong>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        style={{ padding: "2px 8px" }}
                        onClick={() => setTotalFloorsCount(form.floors.length + 1)}
                      >
                        +
                      </button>
                    </div>
                  </div>

                  {/* Floor Rows List */}
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px", marginTop: "16px" }}>
                    {form.floors.map((floor, idx) => (
                      <div
                        key={idx}
                        style={{
                          background: idx === 0 ? "rgba(16, 185, 129, 0.05)" : "var(--bg-secondary)",
                          border: idx === 0 ? "1px solid rgba(16, 185, 129, 0.3)" : "1px solid var(--border-light)",
                          padding: "10px 12px",
                          borderRadius: "10px",
                          display: "grid",
                          gridTemplateColumns: "75px 1.4fr 70px 1fr 30px",
                          gap: "8px",
                          alignItems: "center",
                        }}
                      >
                        {/* Floor Indicator Badge */}
                        <div>
                          <span
                            style={{
                              fontSize: "0.72rem",
                              fontWeight: "700",
                              padding: "3px 6px",
                              borderRadius: "4px",
                              background: idx === 0 ? "var(--primary-color, #10B981)" : "var(--bg-card)",
                              color: idx === 0 ? "#fff" : "var(--text-secondary)",
                              display: "inline-block",
                              border: idx === 0 ? "none" : "1px solid var(--border-light)",
                            }}
                          >
                            {idx === 0 ? "Base" : `Floor ${idx}`}
                          </span>
                        </div>

                        {/* Floor Name */}
                        <div>
                          <input
                            type="text"
                            className="form-input form-input-sm"
                            placeholder={idx === 0 ? "Ground Floor" : `Level ${idx}`}
                            value={floor.name}
                            onChange={(e) => updateFloorField(idx, "name", e.target.value)}
                          />
                        </div>

                        {/* Short Code */}
                        <div>
                          <input
                            type="text"
                            maxLength={6}
                            className="form-input form-input-sm"
                            placeholder={idx === 0 ? "G" : `L${idx}`}
                            value={floor.short_code}
                            onChange={(e) => updateFloorField(idx, "short_code", e.target.value.toUpperCase())}
                            style={{ fontFamily: "monospace", textAlign: "center", fontWeight: "700" }}
                          />
                        </div>

                        {/* Level Type */}
                        <div>
                          <select
                            className="form-select form-select-sm"
                            value={floor.level_type || "indoor_floor"}
                            onChange={(e) => updateFloorField(idx, "level_type", e.target.value)}
                          >
                            {LEVEL_TYPES.map((lt) => (
                              <option key={lt.value} value={lt.value}>
                                {lt.label}
                              </option>
                            ))}
                          </select>
                        </div>

                        {/* Remove button */}
                        <div>
                          {idx > 0 && (
                            <button
                              type="button"
                              className="btn btn-ghost btn-sm"
                              onClick={() => removeFloor(idx)}
                              style={{ color: "var(--error, #EF4444)", padding: "4px" }}
                              title="Remove this floor"
                            >
                              <LuTrash2 size={15} />
                            </button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Add Floor Button */}
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={addFloor}
                    style={{ marginTop: "14px", display: "inline-flex", alignItems: "center", gap: "6px" }}
                  >
                    <LuPlus size={15} /> Add Another Floor Level
                  </button>
                </div>
              </div>

              {/* Side Panel Sticky Footer */}
              <div
                style={{
                  display: "flex",
                  justifyContent: "flex-end",
                  gap: "12px",
                  borderTop: "1px solid var(--border-light)",
                  padding: "16px 24px",
                  background: "var(--bg-secondary)",
                  flexShrink: 0,
                }}
              >
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => setPanelOpen(false)}
                  disabled={submitting}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={submitting}
                  style={{ display: "flex", alignItems: "center", gap: "6px" }}
                >
                  {submitting ? <div className="spinner spinner-sm"></div> : <LuCheck size={16} />}
                  <span>{editingVenue ? "Save Changes" : "Register Venue"}</span>
                </button>
              </div>
            </form>
          </aside>
        </>
      )}
    </div>
  );
}
