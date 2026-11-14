import { useEffect, useState, useCallback, useMemo } from "react";
import { useAuth } from "../context/AuthContext";
import { useToast } from "../components/Toast";
import { api } from "../utils/api";
import { supabase, isSupabaseConfigured } from "../utils/supabaseClient";
import {
  LuPackageSearch,
  LuSearch,
  LuPlus,
  LuFilter,
  LuMapPin,
  LuClock,
  LuCircleCheck,
  LuCircleAlert,
  LuTrash2,
  LuImage,
  LuRefreshCw,
  LuRadio,
  LuCheck,
  LuX,
  LuInfo,
  LuExternalLink
} from "react-icons/lu";

const CATEGORIES = [
  { id: "all", label: "All Categories" },
  { id: "electronics", label: "Electronics" },
  { id: "wallet", label: "Wallet" },
  { id: "id_card", label: "ID Card / Badge" },
  { id: "bag", label: "Bag / Backpack" },
  { id: "clothing", label: "Clothing" },
  { id: "keys", label: "Keys" },
  { id: "other", label: "Other" },
];

const STATUS_CONFIG = {
  submitted: { label: "Submitted / Open", badgeClass: "badge-warning", color: "var(--yellow-400)" },
  in_review: { label: "In Review", badgeClass: "badge-info", color: "var(--blue-400)" },
  matched: { label: "Matched", badgeClass: "badge-purple", color: "#a855f7" },
  resolved: { label: "Resolved / Returned", badgeClass: "badge-success", color: "var(--green-400)" },
  draft: { label: "Draft", badgeClass: "badge-secondary", color: "var(--text-muted)" },
};

export default function OrganizerLostFound() {
  const { user: _user } = useAuth();
  const toast = useToast();

  const [events, setEvents] = useState([]);
  const [selectedEventId, setSelectedEventId] = useState("");
  const [zones, setZones] = useState([]);
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [typeFilter, setTypeFilter] = useState("all"); // 'all', 'lost', 'found'
  const [statusFilter, setStatusFilter] = useState("all");
  const [categoryFilter, setCategoryFilter] = useState("all");

  // Create Modal
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [createSubmitting, setCreateSubmitting] = useState(false);
  const [newItem, setNewItem] = useState({
    report_type: "found",
    category: "electronics",
    title: "",
    description: "",
    zone_id: "",
    venue_zone_name: "",
    specific_location: "",
    image_url: "",
    status: "submitted",
    pickup_instructions: "",
  });

  // Edit / Status Modal
  const [activeItem, setActiveItem] = useState(null);
  const [editStatus, setEditStatus] = useState("submitted");
  const [editInstructions, setEditInstructions] = useState("");
  const [updatingStatus, setUpdatingStatus] = useState(false);

  // Photo viewer
  const [previewPhoto, setPreviewPhoto] = useState(null);

  // Load Organizer Events
  useEffect(() => {
    api.get("/api/events/organizer/mine")
      .then((data) => {
        const evList = data.events || [];
        setEvents(evList);
        if (evList.length > 0) {
          const liveEvent =
            evList.find((e) => e.status === "live") ||
            evList.find((e) => e.status === "upcoming") ||
            evList[0];
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

  // Load Zones & Items for Selected Event
  const fetchItems = useCallback(
    (silent = false) => {
      if (!selectedEventId) return;
      if (!silent) setLoading(true);
      setIsRefreshing(true);

      Promise.all([
        api.get(`/api/organizer/lost-found/${selectedEventId}`),
        api.get(`/api/organizer/zones/${selectedEventId}`).catch(() => ({ zones: [] })),
      ])
        .then(([lfData, zData]) => {
          setItems(lfData.items || []);
          setZones(zData.zones || []);
        })
        .catch((err) => toast(err.message, "error"))
        .finally(() => {
          setLoading(false);
          setIsRefreshing(false);
        });
    },
    [selectedEventId, toast]
  );

  useEffect(() => {
    fetchItems();

    // Supabase Realtime synchronization on lost_found_reports
    let channel = null;
    if (isSupabaseConfigured && selectedEventId) {
      channel = supabase
        .channel(`org-lf-${selectedEventId}`)
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "lost_found_reports",
            filter: `event_id=eq.${selectedEventId}`,
          },
          () => {
            fetchItems(true);
          }
        )
        .subscribe();
    }

    return () => {
      if (channel) supabase.removeChannel(channel);
    };
  }, [selectedEventId, fetchItems]);

  // Handle Create Submit
  const handleCreateSubmit = async (e) => {
    e.preventDefault();
    if (!newItem.title.trim()) {
      toast("Please enter an item title", "warning");
      return;
    }

    setCreateSubmitting(true);
    try {
      const selectedZone = zones.find((z) => z.id === newItem.zone_id);
      await api.post("/api/organizer/lost-found", {
        event_id: selectedEventId,
        report_type: newItem.report_type,
        category: newItem.category,
        title: newItem.title.trim(),
        description: newItem.description.trim(),
        zone_id: newItem.zone_id || null,
        venue_zone_name: selectedZone ? selectedZone.name : newItem.venue_zone_name || null,
        specific_location: newItem.specific_location.trim() || null,
        image_url: newItem.image_url.trim() || null,
        status: newItem.status,
        pickup_instructions: newItem.pickup_instructions.trim() || null,
      });

      toast(`Report for "${newItem.title}" created successfully!`, "success");
      setIsCreateOpen(false);
      setNewItem({
        report_type: "found",
        category: "electronics",
        title: "",
        description: "",
        zone_id: "",
        venue_zone_name: "",
        specific_location: "",
        image_url: "",
        status: "submitted",
        pickup_instructions: "",
      });
      fetchItems();
    } catch (err) {
      toast(err.message || "Failed to create report", "error");
    } finally {
      setCreateSubmitting(false);
    }
  };

  // Open Update Modal
  const openUpdateModal = (item) => {
    setActiveItem(item);
    setEditStatus(item.status || "submitted");
    setEditInstructions(item.pickup_instructions || "");
  };

  // Handle Update Status Submit
  const handleUpdateStatusSubmit = async (e) => {
    e.preventDefault();
    if (!activeItem) return;

    setUpdatingStatus(true);
    try {
      await api.put(`/api/organizer/lost-found/${activeItem.id}`, {
        status: editStatus,
        pickup_instructions: editInstructions.trim() || null,
      });

      toast(`Item "${activeItem.title}" updated.`, "success");
      setActiveItem(null);
      fetchItems(true);
    } catch (err) {
      toast(err.message || "Failed to update item", "error");
    } finally {
      setUpdatingStatus(false);
    }
  };

  // Handle Quick Match
  const handleQuickMatch = async (item) => {
    try {
      await api.put(`/api/organizer/lost-found/${item.id}`, {
        status: "matched",
      });
      toast(`"${item.title}" marked as Matched!`, "success");
      fetchItems(true);
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // Handle Delete
  const handleDeleteItem = async (item) => {
    if (!window.confirm(`Are you sure you want to delete "${item.title}"?`)) return;

    try {
      await api.delete(`/api/organizer/lost-found/${item.id}`);
      toast(`Deleted "${item.title}".`, "success");
      setItems((prev) => prev.filter((i) => i.id !== item.id));
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // Filtered Items
  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      if (typeFilter !== "all" && item.report_type?.toLowerCase() !== typeFilter) return false;
      if (statusFilter !== "all" && item.status?.toLowerCase() !== statusFilter) return false;
      if (categoryFilter !== "all" && item.category?.toLowerCase() !== categoryFilter) return false;

      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const titleMatch = item.title?.toLowerCase().includes(q);
        const descMatch = item.description?.toLowerCase().includes(q);
        const locMatch = item.specific_location?.toLowerCase().includes(q) || item.venue_zone_name?.toLowerCase().includes(q);
        const catMatch = item.category?.toLowerCase().includes(q);
        if (!titleMatch && !descMatch && !locMatch && !catMatch) return false;
      }

      return true;
    });
  }, [items, typeFilter, statusFilter, categoryFilter, searchQuery]);

  // Statistics
  const stats = useMemo(() => {
    const total = items.length;
    const lostCount = items.filter((i) => i.report_type === "lost").length;
    const foundCount = items.filter((i) => i.report_type === "found").length;
    const resolvedCount = items.filter((i) => i.status === "resolved" || i.status === "matched").length;
    return { total, lostCount, foundCount, resolvedCount };
  }, [items]);

  const zoneMap = useMemo(() => new Map(zones.map((z) => [z.id, z.name])), [zones]);

  return (
    <div className="page-container" style={{ padding: "1.5rem" }}>
      {/* Top Header */}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          flexWrap: "wrap",
          gap: "1rem",
          marginBottom: "1.5rem",
        }}
      >
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
            <LuPackageSearch style={{ fontSize: "1.75rem", color: "var(--primary-400, #38bdf8)" }} />
            <h1 style={{ fontSize: "1.5rem", fontWeight: 700, margin: 0 }}>Lost & Found Operations</h1>
            <span
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: "0.35rem",
                fontSize: "0.75rem",
                padding: "0.2rem 0.5rem",
                borderRadius: "9999px",
                background: "rgba(34, 197, 94, 0.12)",
                color: "var(--green-400, #4ade80)",
                border: "1px solid rgba(34, 197, 94, 0.25)",
                marginLeft: "0.5rem",
              }}
            >
              <LuRadio style={{ animation: "pulse 2s infinite" }} />
              Live Sync
            </span>
          </div>
          <p style={{ margin: "0.25rem 0 0 0", color: "var(--text-muted)", fontSize: "0.875rem" }}>
            Centralized intake, volunteer mobile coordination, and return desk logging.
          </p>
        </div>

        {/* Action Controls & Event Select */}
        <div style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
          <select
            className="input-field"
            style={{ width: "auto", minWidth: "200px" }}
            value={selectedEventId}
            onChange={(e) => setSelectedEventId(e.target.value)}
          >
            {events.map((ev) => (
              <option key={ev.id} value={ev.id}>
                {ev.name} ({ev.status})
              </option>
            ))}
          </select>

          <button
            className="btn btn-secondary"
            onClick={() => fetchItems()}
            disabled={isRefreshing}
            title="Refresh items"
            style={{ display: "flex", alignItems: "center", gap: "0.4rem" }}
          >
            <LuRefreshCw className={isRefreshing ? "spin" : ""} />
            Refresh
          </button>

          <button
            className="btn btn-primary"
            onClick={() => setIsCreateOpen(true)}
            style={{ display: "flex", alignItems: "center", gap: "0.4rem" }}
          >
            <LuPlus />
            Log New Item
          </button>
        </div>
      </div>

      {/* Metrics Row */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))",
          gap: "1rem",
          marginBottom: "1.5rem",
        }}
      >
        <div className="card" style={{ padding: "1rem 1.25rem" }}>
          <div style={{ color: "var(--text-muted)", fontSize: "0.8rem", textTransform: "uppercase", fontWeight: 600 }}>
            Total Cataloged
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: 800, marginTop: "0.25rem" }}>{stats.total}</div>
        </div>

        <div className="card" style={{ padding: "1rem 1.25rem", borderLeft: "4px solid #ef4444" }}>
          <div style={{ color: "var(--text-muted)", fontSize: "0.8rem", textTransform: "uppercase", fontWeight: 600 }}>
            Lost Inquiries
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: 800, color: "#f87171", marginTop: "0.25rem" }}>
            {stats.lostCount}
          </div>
        </div>

        <div className="card" style={{ padding: "1rem 1.25rem", borderLeft: "4px solid #38bdf8" }}>
          <div style={{ color: "var(--text-muted)", fontSize: "0.8rem", textTransform: "uppercase", fontWeight: 600 }}>
            Found & Recovered
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: 800, color: "#38bdf8", marginTop: "0.25rem" }}>
            {stats.foundCount}
          </div>
        </div>

        <div className="card" style={{ padding: "1rem 1.25rem", borderLeft: "4px solid var(--green-400, #4ade80)" }}>
          <div style={{ color: "var(--text-muted)", fontSize: "0.8rem", textTransform: "uppercase", fontWeight: 600 }}>
            Resolved / Matched
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: 800, color: "var(--green-400, #4ade80)", marginTop: "0.25rem" }}>
            {stats.resolvedCount}
          </div>
        </div>
      </div>

      {/* Search & Filters Bar */}
      <div
        className="card"
        style={{
          padding: "1rem",
          marginBottom: "1.5rem",
          display: "flex",
          flexWrap: "wrap",
          gap: "1rem",
          alignItems: "center",
        }}
      >
        {/* Search */}
        <div style={{ position: "relative", flex: "1 1 240px", minWidth: "220px" }}>
          <LuSearch
            style={{
              position: "absolute",
              left: "0.75rem",
              top: "50%",
              transform: "translateY(-50%)",
              color: "var(--text-muted)",
            }}
          />
          <input
            type="text"
            className="input-field"
            placeholder="Search items, descriptions, locations..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{ paddingLeft: "2.25rem", width: "100%" }}
          />
        </div>

        {/* Type Filter Buttons */}
        <div style={{ display: "flex", borderRadius: "8px", overflow: "hidden", border: "1px solid var(--border-default)" }}>
          {[
            { id: "all", label: "All Items" },
            { id: "lost", label: "Lost Only" },
            { id: "found", label: "Found Only" },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setTypeFilter(tab.id)}
              style={{
                padding: "0.5rem 0.9rem",
                fontSize: "0.85rem",
                fontWeight: 600,
                border: "none",
                cursor: "pointer",
                background: typeFilter === tab.id ? "var(--primary-600, #0284c7)" : "var(--bg-secondary)",
                color: typeFilter === tab.id ? "#fff" : "var(--text-secondary)",
                transition: "background 0.2s",
              }}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Status Filter */}
        <div style={{ minWidth: "160px" }}>
          <select
            className="input-field"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            style={{ width: "100%" }}
          >
            <option value="all">All Statuses</option>
            <option value="submitted">Submitted / Open</option>
            <option value="in_review">In Review</option>
            <option value="matched">Matched</option>
            <option value="resolved">Resolved / Returned</option>
          </select>
        </div>

        {/* Category Filter */}
        <div style={{ minWidth: "160px" }}>
          <select
            className="input-field"
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            style={{ width: "100%" }}
          >
            {CATEGORIES.map((cat) => (
              <option key={cat.id} value={cat.id}>
                {cat.label}
              </option>
            ))}
          </select>
        </div>

        {(searchQuery || typeFilter !== "all" || statusFilter !== "all" || categoryFilter !== "all") && (
          <button
            className="btn btn-secondary"
            onClick={() => {
              setSearchQuery("");
              setTypeFilter("all");
              setStatusFilter("all");
              setCategoryFilter("all");
            }}
            style={{ fontSize: "0.8rem", padding: "0.45rem 0.75rem" }}
          >
            Reset Filters
          </button>
        )}
      </div>

      {/* Main Content: Item List */}
      {loading ? (
        <div className="card" style={{ padding: "3rem", textAlign: "center" }}>
          <div className="spinner spinner-lg" style={{ margin: "0 auto 1rem" }}></div>
          <p style={{ color: "var(--text-muted)" }}>Loading Lost & Found items...</p>
        </div>
      ) : filteredItems.length === 0 ? (
        <div className="card" style={{ padding: "3.5rem 1.5rem", textAlign: "center" }}>
          <LuPackageSearch style={{ fontSize: "3rem", color: "var(--text-muted)", opacity: 0.5, marginBottom: "1rem" }} />
          <h3 style={{ fontSize: "1.15rem", fontWeight: 600, margin: "0 0 0.5rem" }}>No items found</h3>
          <p style={{ color: "var(--text-muted)", fontSize: "0.9rem", maxWidth: "420px", margin: "0 auto 1.5rem" }}>
            {items.length === 0
              ? "No lost or found items have been cataloged for this event yet. Use the Log New Item button or volunteer mobile app to intake items."
              : "No items match your active search or filter criteria."}
          </p>
          <button className="btn btn-primary" onClick={() => setIsCreateOpen(true)}>
            <LuPlus /> Log New Item
          </button>
        </div>
      ) : (
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))",
            gap: "1.25rem",
          }}
        >
          {filteredItems.map((item) => {
            const isLost = item.report_type === "lost";
            const statusMeta = STATUS_CONFIG[item.status] || {
              label: item.status,
              badgeClass: "badge-secondary",
              color: "var(--text-muted)",
            };

            return (
              <div
                key={item.id}
                className="card"
                style={{
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "space-between",
                  padding: "1.25rem",
                  position: "relative",
                  borderTop: isLost ? "4px solid #ef4444" : "4px solid #0284c7",
                }}
              >
                <div>
                  {/* Top Badges */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.75rem" }}>
                    <div style={{ display: "flex", gap: "0.4rem", alignItems: "center" }}>
                      <span
                        style={{
                          padding: "0.2rem 0.6rem",
                          borderRadius: "6px",
                          fontSize: "0.75rem",
                          fontWeight: 700,
                          textTransform: "uppercase",
                          letterSpacing: "0.5px",
                          backgroundColor: isLost ? "rgba(239, 68, 68, 0.15)" : "rgba(2, 132, 199, 0.15)",
                          color: isLost ? "#f87171" : "#38bdf8",
                        }}
                      >
                        {isLost ? "Lost" : "Found"}
                      </span>
                      <span
                        style={{
                          padding: "0.2rem 0.5rem",
                          borderRadius: "6px",
                          fontSize: "0.75rem",
                          background: "var(--bg-secondary)",
                          color: "var(--text-secondary)",
                          textTransform: "capitalize",
                        }}
                      >
                        {item.category?.replace("_", " ") || "General"}
                      </span>
                    </div>

                    <span
                      style={{
                        padding: "0.2rem 0.55rem",
                        borderRadius: "9999px",
                        fontSize: "0.75rem",
                        fontWeight: 600,
                        backgroundColor: "var(--bg-secondary)",
                        color: statusMeta.color,
                        border: `1px solid ${statusMeta.color}33`,
                      }}
                    >
                      {statusMeta.label}
                    </span>
                  </div>

                  {/* Item Title & Description */}
                  <h3 style={{ fontSize: "1.1rem", fontWeight: 700, margin: "0 0 0.4rem 0" }}>
                    {item.title}
                  </h3>
                  {item.description && (
                    <p
                      style={{
                        fontSize: "0.875rem",
                        color: "var(--text-secondary)",
                        margin: "0 0 0.85rem 0",
                        lineHeight: 1.45,
                        display: "-webkit-box",
                        WebkitLineClamp: 3,
                        WebkitBoxOrient: "vertical",
                        overflow: "hidden",
                      }}
                    >
                      {item.description}
                    </p>
                  )}

                  {/* Location & Time Info */}
                  <div style={{ display: "flex", flexDirection: "column", gap: "0.35rem", marginBottom: "0.85rem", fontSize: "0.825rem", color: "var(--text-muted)" }}>
                    {(() => {
                      const zoneName = item.event_zones?.name || (item.zone_id ? zoneMap.get(item.zone_id) : null) || item.venue_zone_name;
                      const loc = [zoneName, item.specific_location].filter(Boolean).join(" • ");
                      if (!loc) return null;
                      return (
                        <div style={{ display: "flex", alignItems: "center", gap: "0.4rem" }}>
                          <LuMapPin style={{ color: "var(--primary-400)" }} />
                          <span>{loc}</span>
                        </div>
                      );
                    })()}
                    <div style={{ display: "flex", alignItems: "center", gap: "0.4rem" }}>
                      <LuClock />
                      <span>{new Date(item.created_at).toLocaleString([], { dateStyle: "short", timeStyle: "short" })}</span>
                      {item.reporter_device_id && (
                        <span style={{ opacity: 0.7 }}>via {item.reporter_device_id}</span>
                      )}
                    </div>
                  </div>

                  {/* Pickup Instructions / Notes */}
                  {item.pickup_instructions && (
                    <div
                      style={{
                        background: "rgba(56, 189, 248, 0.08)",
                        border: "1px dashed rgba(56, 189, 248, 0.3)",
                        padding: "0.5rem 0.75rem",
                        borderRadius: "6px",
                        fontSize: "0.8rem",
                        color: "var(--text-primary)",
                        marginBottom: "0.85rem",
                      }}
                    >
                      <strong style={{ color: "var(--primary-400)" }}>Pickup: </strong>
                      {item.pickup_instructions}
                    </div>
                  )}

                  {/* Attached Image Thumbnail */}
                  {item.image_url && (
                    <div style={{ marginBottom: "0.85rem" }}>
                      <button
                        type="button"
                        onClick={() => setPreviewPhoto(item.image_url)}
                        style={{
                          background: "none",
                          border: "none",
                          padding: 0,
                          cursor: "pointer",
                          display: "flex",
                          alignItems: "center",
                          gap: "0.4rem",
                          color: "var(--primary-400)",
                          fontSize: "0.8rem",
                        }}
                      >
                        <LuImage />
                        <span>View Attached Photo</span>
                      </button>
                    </div>
                  )}
                </div>

                {/* Card Action Footer */}
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    borderTop: "1px solid var(--border-default)",
                    paddingTop: "0.85rem",
                    marginTop: "0.5rem",
                  }}
                >
                  <div style={{ display: "flex", gap: "0.5rem" }}>
                    <button
                      className="btn btn-secondary"
                      style={{ fontSize: "0.775rem", padding: "0.35rem 0.7rem" }}
                      onClick={() => openUpdateModal(item)}
                    >
                      Update Status
                    </button>
                    {item.status !== "matched" && item.status !== "resolved" && (
                      <button
                        className="btn btn-secondary"
                        style={{ fontSize: "0.775rem", padding: "0.35rem 0.6rem", color: "#a855f7" }}
                        onClick={() => handleQuickMatch(item)}
                        title="Mark as matched with counterpart"
                      >
                        Match
                      </button>
                    )}
                  </div>

                  <button
                    onClick={() => handleDeleteItem(item)}
                    style={{
                      background: "none",
                      border: "none",
                      color: "var(--text-muted)",
                      cursor: "pointer",
                      padding: "0.35rem",
                      borderRadius: "4px",
                    }}
                    title="Delete report"
                  >
                    <LuTrash2 style={{ fontSize: "1rem" }} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* CREATE ITEM MODAL */}
      {isCreateOpen && (
        <div className="modal-overlay" onClick={() => setIsCreateOpen(false)}>
          <div
            className="modal-content"
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: "560px", width: "100%", maxHeight: "90vh", overflowY: "auto" }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.25rem" }}>
              <h2 style={{ fontSize: "1.25rem", fontWeight: 700, margin: 0 }}>Log Lost & Found Report</h2>
              <button
                onClick={() => setIsCreateOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: "1.2rem" }}
              >
                <LuX />
              </button>
            </div>

            <form onSubmit={handleCreateSubmit}>
              {/* Report Type Toggle */}
              <div style={{ marginBottom: "1rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.5rem" }}>
                  Report Classification
                </label>
                <div style={{ display: "flex", gap: "0.75rem" }}>
                  <button
                    type="button"
                    onClick={() => setNewItem({ ...newItem, report_type: "found" })}
                    style={{
                      flex: 1,
                      padding: "0.75rem",
                      borderRadius: "8px",
                      border: newItem.report_type === "found" ? "2px solid #0284c7" : "1px solid var(--border-default)",
                      background: newItem.report_type === "found" ? "rgba(2, 132, 199, 0.12)" : "var(--bg-secondary)",
                      color: newItem.report_type === "found" ? "#38bdf8" : "var(--text-secondary)",
                      fontWeight: 700,
                      cursor: "pointer",
                      display: "flex",
                      justifyContent: "center",
                      alignItems: "center",
                      gap: "0.5rem",
                    }}
                  >
                    <LuCircleCheck /> Found Item
                  </button>
                  <button
                    type="button"
                    onClick={() => setNewItem({ ...newItem, report_type: "lost" })}
                    style={{
                      flex: 1,
                      padding: "0.75rem",
                      borderRadius: "8px",
                      border: newItem.report_type === "lost" ? "2px solid #ef4444" : "1px solid var(--border-default)",
                      background: newItem.report_type === "lost" ? "rgba(239, 68, 68, 0.12)" : "var(--bg-secondary)",
                      color: newItem.report_type === "lost" ? "#f87171" : "var(--text-secondary)",
                      fontWeight: 700,
                      cursor: "pointer",
                      display: "flex",
                      justifyContent: "center",
                      alignItems: "center",
                      gap: "0.5rem",
                    }}
                  >
                    <LuCircleAlert /> Lost Item Inquiry
                  </button>
                </div>
              </div>

              {/* Title & Category */}
              <div style={{ display: "grid", gridTemplateColumns: "1.5fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
                <div>
                  <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                    Item Title *
                  </label>
                  <input
                    type="text"
                    className="input-field"
                    required
                    placeholder="e.g. iPhone 15 Pro with Blue Case"
                    value={newItem.title}
                    onChange={(e) => setNewItem({ ...newItem, title: e.target.value })}
                  />
                </div>
                <div>
                  <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                    Category
                  </label>
                  <select
                    className="input-field"
                    value={newItem.category}
                    onChange={(e) => setNewItem({ ...newItem, category: e.target.value })}
                  >
                    {CATEGORIES.filter((c) => c.id !== "all").map((cat) => (
                      <option key={cat.id} value={cat.id}>
                        {cat.label}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {/* Description */}
              <div style={{ marginBottom: "1rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                  Description & Identifying Characteristics
                </label>
                <textarea
                  className="input-field"
                  rows={3}
                  placeholder="Distinctive marks, stickers, serial details, color..."
                  value={newItem.description}
                  onChange={(e) => setNewItem({ ...newItem, description: e.target.value })}
                />
              </div>

              {/* Location: Zone & Specific */}
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem", marginBottom: "1rem" }}>
                <div>
                  <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                    Event Zone / Room
                  </label>
                  <select
                    className="input-field"
                    value={newItem.zone_id}
                    onChange={(e) => setNewItem({ ...newItem, zone_id: e.target.value })}
                  >
                    <option value="">Select Zone (Optional)</option>
                    {zones.map((z) => (
                      <option key={z.id} value={z.id}>
                        {z.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                    Specific Location
                  </label>
                  <input
                    type="text"
                    className="input-field"
                    placeholder="e.g. Near Booth 14, Main Hall"
                    value={newItem.specific_location}
                    onChange={(e) => setNewItem({ ...newItem, specific_location: e.target.value })}
                  />
                </div>
              </div>

              {/* Image URL & Pickup Instructions */}
              <div style={{ marginBottom: "1rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                  Photo URL (Optional)
                </label>
                <input
                  type="url"
                  className="input-field"
                  placeholder="https://images.example.com/item.jpg"
                  value={newItem.image_url}
                  onChange={(e) => setNewItem({ ...newItem, image_url: e.target.value })}
                />
              </div>

              <div style={{ marginBottom: "1.25rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                  Pickup & Storage Instructions
                </label>
                <input
                  type="text"
                  className="input-field"
                  placeholder="e.g. Handed to Desk 1; owner must verify lock screen"
                  value={newItem.pickup_instructions}
                  onChange={(e) => setNewItem({ ...newItem, pickup_instructions: e.target.value })}
                />
              </div>

              {/* Modal Buttons */}
              <div style={{ display: "flex", justifyContent: "flex-end", gap: "0.75rem" }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setIsCreateOpen(false)}
                  disabled={createSubmitting}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={createSubmitting}>
                  {createSubmitting ? "Saving..." : "Save Report"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* UPDATE STATUS MODAL */}
      {activeItem && (
        <div className="modal-overlay" onClick={() => setActiveItem(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: "480px", width: "100%" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.25rem" }}>
              <h2 style={{ fontSize: "1.2rem", fontWeight: 700, margin: 0 }}>Update "{activeItem.title}"</h2>
              <button
                onClick={() => setActiveItem(null)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: "1.2rem" }}
              >
                <LuX />
              </button>
            </div>

            <form onSubmit={handleUpdateStatusSubmit}>
              <div style={{ marginBottom: "1rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                  Status
                </label>
                <select
                  className="input-field"
                  value={editStatus}
                  onChange={(e) => setEditStatus(e.target.value)}
                >
                  <option value="submitted">Submitted / Open</option>
                  <option value="in_review">In Review / Investigating</option>
                  <option value="matched">Matched with Owner / Item</option>
                  <option value="resolved">Resolved / Returned to Owner</option>
                </select>
              </div>

              <div style={{ marginBottom: "1.25rem" }}>
                <label className="form-label" style={{ fontWeight: 600, display: "block", marginBottom: "0.35rem" }}>
                  Pickup & Verification Instructions
                </label>
                <textarea
                  className="input-field"
                  rows={3}
                  placeholder="e.g. Stored in North Security safe. Claim with government photo ID."
                  value={editInstructions}
                  onChange={(e) => setEditInstructions(e.target.value)}
                />
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "0.75rem" }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setActiveItem(null)}
                  disabled={updatingStatus}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={updatingStatus}>
                  {updatingStatus ? "Updating..." : "Update Status"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* PHOTO PREVIEW MODAL */}
      {previewPhoto && (
        <div className="modal-overlay" onClick={() => setPreviewPhoto(null)}>
          <div
            className="modal-content"
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: "600px", padding: "1rem", textAlign: "center" }}
          >
            <div style={{ display: "flex", justifyContent: "flex-end", marginBottom: "0.5rem" }}>
              <button
                onClick={() => setPreviewPhoto(null)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: "1.2rem" }}
              >
                <LuX />
              </button>
            </div>
            <img
              src={previewPhoto}
              alt="Item preview"
              style={{ maxWidth: "100%", maxHeight: "70vh", borderRadius: "8px", objectFit: "contain" }}
            />
          </div>
        </div>
      )}
    </div>
  );
}
