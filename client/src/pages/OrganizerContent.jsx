import { useEffect, useState, useCallback, useMemo } from "react";
import { useAuth } from "../context/AuthContext";
import { useToast } from "../components/Toast";
import { api } from "../utils/api";
import { 
  LuAward,
  LuStore, 
  LuPlus, 
  LuPencil, 
  LuTrash2, 
  LuMapPin, 
  LuClock, 
  LuTrophy, 
  LuSparkles,
  LuExternalLink,
  LuSearch,
  LuBuilding,
  LuMail,
  LuCircleCheck,
  LuCircleAlert,
  LuCalendarPlus,
  LuX,
  LuGlobe,
  LuBot,
  LuCheck,
  LuSend,
  LuRadio
} from "react-icons/lu";

const SPONSOR_TIERS = [
  "Title Sponsor",
  "Platinum Sponsor",
  "Gold Sponsor",
  "Silver Sponsor",
  "Official Partner",
  "Tech Partner",
  "Brand Exhibitor",
  "Food & Beverage",
  "Community Partner",
];

const getTierBadgeStyle = (tier) => {
  const t = (tier || "").toLowerCase();
  if (t.includes("title")) {
    return { bg: "rgba(234, 179, 8, 0.15)", color: "#FACC15", border: "1px solid rgba(234, 179, 8, 0.4)", label: tier || "Title Sponsor" };
  }
  if (t.includes("platinum")) {
    return { bg: "rgba(56, 189, 248, 0.15)", color: "#7DD3FC", border: "1px solid rgba(56, 189, 248, 0.4)", label: tier || "Platinum" };
  }
  if (t.includes("gold")) {
    return { bg: "rgba(245, 158, 11, 0.15)", color: "#FBBF24", border: "1px solid rgba(245, 158, 11, 0.4)", label: tier || "Gold" };
  }
  if (t.includes("silver")) {
    return { bg: "rgba(148, 163, 184, 0.15)", color: "#CBD5E1", border: "1px solid rgba(148, 163, 184, 0.4)", label: tier || "Silver" };
  }
  if (t.includes("partner") || t.includes("tech")) {
    return { bg: "rgba(16, 185, 129, 0.15)", color: "#34D399", border: "1px solid rgba(16, 185, 129, 0.4)", label: tier || "Partner" };
  }
  return { bg: "rgba(168, 85, 247, 0.15)", color: "#C084FC", border: "1px solid rgba(168, 85, 247, 0.4)", label: tier || "Exhibitor" };
};

export default function OrganizerContent() {
  const { user: _user } = useAuth();
  const toast = useToast();
  const [events, setEvents] = useState([]);
  const [selectedEventId, setSelectedEventId] = useState("");
  const [activeTab, setActiveTab] = useState("sponsors"); // 'sponsors' | 'sessions' | 'activities'
  
  // Data states
  const [sponsors, setSponsors] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [activities, setActivities] = useState([]);
  const [zones, setZones] = useState([]);
  const [loading, setLoading] = useState(true);

  // Filters & Search
  const [searchTerm, setSearchTerm] = useState("");
  const [tierFilter, setTierFilter] = useState("all");
  const [locationFilter, setLocationFilter] = useState("all");

  // Modals for Sponsors
  const [isSponsorModalOpen, setIsSponsorModalOpen] = useState(false);
  const [editingSponsor, setEditingSponsor] = useState(null);
  const [sponsorForm, setSponsorForm] = useState({ 
    name: "", 
    company_name: "", 
    category: "Title Sponsor", 
    booth_number: "", 
    zone_id: "", 
    description: "",
    website_url: "",
    contact_name: "",
    contact_email: "",
    is_active: true
  });

  // Modal for Quick Location Assignment
  const [isLocationModalOpen, setIsLocationModalOpen] = useState(false);
  const [locatingSponsor, setLocatingSponsor] = useState(null);
  const [locationForm, setLocationForm] = useState({ zone_id: "", booth_number: "" });

  // AI Quest Generator Agent States
  const [isAiQuestModalOpen, setIsAiQuestModalOpen] = useState(false);
  const [aiQuestLoading, setAiQuestLoading] = useState(false);
  const [aiQuestSaving, setAiQuestSaving] = useState(false);
  const [aiQuestInput, setAiQuestInput] = useState({
    brand_name: "",
    has_stall: false,
    zone_id: "",
    booth_number: "",
    website_url: "",
    category: "Title Sponsor",
    points_tier: 100,
  });
  const [generatedQuest, setGeneratedQuest] = useState(null);

  // Modals for Sessions & Activities
  const [isSessionModalOpen, setIsSessionModalOpen] = useState(false);
  const [editingSession, setEditingSession] = useState(null);
  const [sessionForm, setSessionForm] = useState({ title: "", speaker_name: "", location: "", zone_id: "", start_time: "", end_time: "", description: "" });

  const [isActivityModalOpen, setIsActivityModalOpen] = useState(false);
  const [editingActivity, setEditingActivity] = useState(null);
  const [activityForm, setActivityForm] = useState({ title: "", description: "", points_reward: 50, zone_id: "", activity_type: "scavenger" });

  // Broadcast Quest Modal States
  const [isBroadcastModalOpen, setIsBroadcastModalOpen] = useState(false);
  const [broadcastingQuest, setBroadcastingQuest] = useState(null);
  const [broadcastTarget, setBroadcastTarget] = useState("all"); // "all" | "zone"
  const [broadcastZoneId, setBroadcastZoneId] = useState("");
  const [broadcastSending, setBroadcastSending] = useState(false);

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

  const fetchContent = useCallback(() => {
    if (!selectedEventId) return;
    setLoading(true);

    const endpoints = [
      api.get(`/api/organizer/zones/${selectedEventId}`).catch(() => ({ zones: [] })),
      api.get(`/api/organizer/booths/${selectedEventId}`).catch(() => ({ booths: [] })),
      api.get(`/api/organizer/sessions/${selectedEventId}`).catch(() => ({ sessions: [] })),
      api.get(`/api/organizer/activities/${selectedEventId}`).catch(() => ({ activities: [] })),
    ];

    Promise.all(endpoints)
      .then(([zoneData, boothData, sessionData, activityData]) => {
        setZones(zoneData.zones || []);
        setSponsors(boothData.booths || []);
        setSessions(sessionData.sessions || []);
        setActivities(activityData.activities || []);
      })
      .catch((err) => toast(err.message, "error"))
      .finally(() => setLoading(false));
  }, [selectedEventId, toast]);

  useEffect(() => {
    fetchContent();
  }, [fetchContent]);

  // Sponsor Handlers
  const handleOpenAddSponsor = () => {
    setEditingSponsor(null);
    setSponsorForm({
      name: "",
      company_name: "",
      category: "Title Sponsor",
      booth_number: "",
      zone_id: "",
      description: "",
      website_url: "",
      contact_name: "",
      contact_email: "",
      is_active: true,
    });
    setIsSponsorModalOpen(true);
  };

  const handleOpenEditSponsor = (s) => {
    setEditingSponsor(s);
    setSponsorForm({
      name: s.name || "",
      company_name: s.company_name || s.name || "",
      category: s.category || "Title Sponsor",
      booth_number: s.booth_number || "",
      zone_id: s.zone_id || "",
      description: s.description || "",
      website_url: s.website_url || "",
      contact_name: s.contact_name || "",
      contact_email: s.contact_email || "",
      is_active: s.is_active !== false,
    });
    setIsSponsorModalOpen(true);
  };

  const handleSaveSponsor = async (e) => {
    e.preventDefault();
    if (!sponsorForm.name.trim()) {
      toast("Brand / Sponsor name is required", "error");
      return;
    }
    try {
      const payload = {
        ...sponsorForm,
        name: sponsorForm.name.trim(),
        company_name: sponsorForm.company_name.trim() || sponsorForm.name.trim(),
        event_id: selectedEventId,
      };

      if (editingSponsor) {
        await api.put(`/api/organizer/booths/${editingSponsor.id}`, payload);
        toast("Brand / Sponsor updated successfully", "success");
      } else {
        await api.post("/api/organizer/booths", payload);
        toast("Brand / Sponsor created successfully", "success");
      }
      setIsSponsorModalOpen(false);
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  const handleDeleteSponsor = async (id, name) => {
    if (!window.confirm(`Are you sure you want to delete ${name || "this brand/sponsor"}?`)) return;
    try {
      await api.delete(`/api/organizer/booths/${id}`);
      toast("Brand / Sponsor deleted", "success");
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // Quick Location Assignment Handlers
  const handleOpenLocationModal = (sponsor) => {
    setLocatingSponsor(sponsor);
    setLocationForm({
      zone_id: sponsor.zone_id || "",
      booth_number: sponsor.booth_number || "",
    });
    setIsLocationModalOpen(true);
  };

  const handleSaveLocation = async (e) => {
    e.preventDefault();
    if (!locatingSponsor) return;
    try {
      await api.put(`/api/organizer/booths/${locatingSponsor.id}/location`, {
        zone_id: locationForm.zone_id || null,
        booth_number: locationForm.booth_number || "",
      });
      toast(`Venue location assigned to ${locatingSponsor.name}`, "success");
      setIsLocationModalOpen(false);
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // AI Quest Generator Agent Handlers
  const handleOpenAiQuest = (sponsor = null) => {
    if (sponsor) {
      const hasStall = Boolean(sponsor.zone_id || sponsor.booth_number);
      setAiQuestInput({
        brand_name: sponsor.name || "",
        has_stall: hasStall,
        zone_id: sponsor.zone_id || "",
        booth_number: sponsor.booth_number || "",
        website_url: sponsor.website_url || "",
        category: sponsor.category || "Title Sponsor",
        points_tier: 100,
      });
    } else {
      const first = sponsors[0];
      setAiQuestInput({
        brand_name: first ? first.name : "",
        has_stall: first ? Boolean(first.zone_id || first.booth_number) : false,
        zone_id: first ? (first.zone_id || "") : "",
        booth_number: first ? (first.booth_number || "") : "",
        website_url: first ? (first.website_url || "") : "",
        category: first ? (first.category || "Title Sponsor") : "Title Sponsor",
        points_tier: 100,
      });
    }
    setGeneratedQuest(null);
    setIsAiQuestModalOpen(true);
  };

  const handleGenerateAiQuest = async () => {
    if (!aiQuestInput.brand_name.trim()) {
      toast("Please enter or select a brand name", "error");
      return;
    }
    setAiQuestLoading(true);
    try {
      const selectedZone = zones.find(z => z.id === aiQuestInput.zone_id);
      const res = await api.post("/api/organizer/ai/generate-quest", {
        event_id: selectedEventId,
        brand_name: aiQuestInput.brand_name.trim(),
        has_stall: aiQuestInput.has_stall,
        zone_id: aiQuestInput.zone_id || null,
        zone_name: selectedZone?.name || null,
        booth_number: aiQuestInput.booth_number || null,
        website_url: aiQuestInput.website_url || null,
        category: aiQuestInput.category || null,
        points_tier: parseInt(aiQuestInput.points_tier, 10) || 100,
      });
      setGeneratedQuest(res.quest);
      toast("AI Quest generated with Gemini 3.5 Flash Lite!", "success");
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setAiQuestLoading(false);
    }
  };

  const handleSaveGeneratedQuest = async () => {
    if (!generatedQuest) return;
    setAiQuestSaving(true);
    try {
      await api.post("/api/organizer/ai/save-quest", {
        event_id: selectedEventId,
        title: generatedQuest.title,
        description: generatedQuest.description,
        activity_type: generatedQuest.activity_type || (generatedQuest.quest_type === "stall_visit" ? "scavenger" : "game"),
        points_reward: parseInt(generatedQuest.points_reward, 10) || 100,
        zone_id: aiQuestInput.zone_id || null,
        is_active: true,
      });
      toast("Quest saved to event! Visible to attendees in Gamified Quests.", "success");
      setIsAiQuestModalOpen(false);
      setGeneratedQuest(null);
      fetchContent();
      setActiveTab("activities");
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setAiQuestSaving(false);
    }
  };

  // Session Handlers
  const handleSaveSession = async (e) => {
    e.preventDefault();
    try {
      if (editingSession) {
        await api.put(`/api/organizer/sessions/${editingSession.id}`, sessionForm);
        toast("Session updated", "success");
      } else {
        await api.post("/api/organizer/sessions", { ...sessionForm, event_id: selectedEventId });
        toast("Session scheduled", "success");
      }
      setIsSessionModalOpen(false);
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  const handleDeleteSession = async (id) => {
    if (!window.confirm("Delete this session?")) return;
    try {
      await api.delete(`/api/organizer/sessions/${id}`);
      toast("Session deleted", "success");
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  // Activity Handlers
  const handleSaveActivity = async (e) => {
    e.preventDefault();
    try {
      const payload = {
        ...activityForm,
        points_reward: parseInt(activityForm.points_reward, 10) || 50,
      };
      if (editingActivity) {
        await api.put(`/api/organizer/activities/${editingActivity.id}`, payload);
        toast("Quest updated", "success");
      } else {
        await api.post("/api/organizer/activities", { ...payload, event_id: selectedEventId });
        toast("Quest created", "success");
      }
      setIsActivityModalOpen(false);
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  const handleDeleteActivity = async (id) => {
    if (!window.confirm("Delete this quest/activity?")) return;
    try {
      await api.delete(`/api/organizer/activities/${id}`);
      toast("Quest deleted", "success");
      fetchContent();
    } catch (err) {
      toast(err.message, "error");
    }
  };

  const handleOpenBroadcastModal = (quest) => {
    setBroadcastingQuest(quest);
    setBroadcastTarget(quest.zone_id ? "zone" : "all");
    setBroadcastZoneId(quest.zone_id || (zones[0]?.id || ""));
    setIsBroadcastModalOpen(true);
  };

  const handleSendQuestBroadcast = async (e) => {
    e.preventDefault();
    if (!broadcastingQuest) return;
    setBroadcastSending(true);
    try {
      const payload = {
        event_id: selectedEventId,
        target: broadcastTarget,
        zone_id: broadcastTarget === "zone" ? broadcastZoneId : null,
      };
      const res = await api.post(`/api/organizer/activities/${broadcastingQuest.id}/broadcast`, payload);
      toast(res.message || "Quest notification broadcast successfully!", "success");
      setIsBroadcastModalOpen(false);
      setBroadcastingQuest(null);
    } catch (err) {
      toast(err.message, "error");
    } finally {
      setBroadcastSending(false);
    }
  };

  // Metrics Calculations
  const metrics = useMemo(() => {
    const total = sponsors.length;
    const titleAndPlatinum = sponsors.filter(s => {
      const cat = (s.category || "").toLowerCase();
      return cat.includes("title") || cat.includes("platinum");
    }).length;
    const goldAndSilver = sponsors.filter(s => {
      const cat = (s.category || "").toLowerCase();
      return cat.includes("gold") || cat.includes("silver");
    }).length;
    const assigned = sponsors.filter(s => s.zone_id || s.booth_number).length;
    return { total, titleAndPlatinum, goldAndSilver, assigned };
  }, [sponsors]);

  // Filtered Sponsors
  const filteredSponsors = useMemo(() => {
    return sponsors.filter((s) => {
      const matchesSearch = 
        !searchTerm ||
        s.name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        s.company_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        s.booth_number?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        s.zone_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        zones.find(z => z.id === s.zone_id)?.name?.toLowerCase().includes(searchTerm.toLowerCase());

      const matchesTier = 
        tierFilter === "all" || 
        s.category?.toLowerCase() === tierFilter.toLowerCase();

      const hasLocation = Boolean(s.zone_id || s.booth_number);
      const matchesLocation = 
        locationFilter === "all" ||
        (locationFilter === "assigned" && hasLocation) ||
        (locationFilter === "unassigned" && !hasLocation);

      return matchesSearch && matchesTier && matchesLocation;
    });
  }, [sponsors, searchTerm, tierFilter, locationFilter, zones]);

  return (
    <div className="fade-in">
      {/* PAGE HEADER */}
      <div className="page-header" style={{ marginBottom: "24px" }}>
        <div>
          <h1 style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <LuAward color="var(--green-400)" size={30} /> Brands & Sponsors
          </h1>
          <p style={{ color: "var(--text-muted)", marginTop: "4px" }}>
            Add sponsors and brand details, then assign venue locations and generate AI-powered attendee quests.
          </p>
        </div>

        <div style={{ display: "flex", gap: "12px", alignItems: "center", flexWrap: "wrap" }}>
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

          {activeTab === "sponsors" && (
            <>
              <button 
                className="btn btn-secondary"
                onClick={() => handleOpenAiQuest(null)}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
              >
                <LuSparkles size={16} color="var(--green-400)" /> AI Quest Agent
              </button>

              <button 
                className="btn btn-primary"
                onClick={handleOpenAddSponsor}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
              >
                <LuPlus size={16} /> Add Brand / Sponsor
              </button>
            </>
          )}

          {activeTab === "sessions" && (
            <button 
              className="btn btn-primary"
              onClick={() => {
                setEditingSession(null);
                setSessionForm({ title: "", speaker_name: "", location: "", zone_id: "", start_time: "", end_time: "", description: "" });
                setIsSessionModalOpen(true);
              }}
            >
              <LuPlus size={16} /> Schedule Session
            </button>
          )}

          {activeTab === "activities" && (
            <>
              <button 
                className="btn btn-secondary"
                onClick={() => handleOpenAiQuest(null)}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
              >
                <LuSparkles size={16} color="var(--green-400)" /> Generate AI Quest
              </button>

              <button 
                className="btn btn-primary"
                onClick={() => {
                  setEditingActivity(null);
                  setActivityForm({ title: "", description: "", points_reward: 50, zone_id: "", activity_type: "scavenger" });
                  setIsActivityModalOpen(true);
                }}
              >
                <LuPlus size={16} /> Create Quest
              </button>
            </>
          )}
        </div>
      </div>

      {/* METRIC OVERVIEW CARDS */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px", marginBottom: "24px" }}>
        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: "600", letterSpacing: "0.5px" }}>
            Total Brands & Sponsors
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: "700", marginTop: "6px", color: "var(--text-primary)" }}>
            {metrics.total}
          </div>
          <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "4px" }}>
            Registered brand partners
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: "600", letterSpacing: "0.5px" }}>
            Title & Platinum
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: "700", marginTop: "6px", color: "#FACC15" }}>
            {metrics.titleAndPlatinum}
          </div>
          <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "4px" }}>
            Top-tier headline sponsors
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: "600", letterSpacing: "0.5px" }}>
            Gold & Silver
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: "700", marginTop: "6px", color: "#38BDF8" }}>
            {metrics.goldAndSilver}
          </div>
          <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "4px" }}>
            Major event contributors
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: "600", letterSpacing: "0.5px" }}>
            Venue Assigned
          </div>
          <div style={{ fontSize: "1.8rem", fontWeight: "700", marginTop: "6px", color: metrics.assigned === metrics.total && metrics.total > 0 ? "var(--green-400)" : "var(--warning)" }}>
            {metrics.assigned} / {metrics.total}
          </div>
          <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "4px" }}>
            {metrics.total - metrics.assigned > 0 ? `${metrics.total - metrics.assigned} await location assignment` : "All brands placed"}
          </div>
        </div>
      </div>

      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        {/* TAB TOGGLES */}
        <div style={{ display: "flex", gap: "10px", padding: "16px 20px", borderBottom: "1px solid var(--border-light)", background: "var(--bg-secondary)" }}>
          <button 
            className={`btn btn-sm ${activeTab === "sponsors" ? "btn-primary" : "btn-ghost"}`}
            onClick={() => setActiveTab("sponsors")}
            style={{ display: "flex", alignItems: "center", gap: "8px" }}
          >
            <LuAward size={16} /> Brands & Sponsors ({sponsors.length})
          </button>
          <button 
            className={`btn btn-sm ${activeTab === "sessions" ? "btn-primary" : "btn-ghost"}`}
            onClick={() => setActiveTab("sessions")}
            style={{ display: "flex", alignItems: "center", gap: "8px" }}
          >
            <LuCalendarPlus size={16} /> Stage Sessions ({sessions.length})
          </button>
          <button 
            className={`btn btn-sm ${activeTab === "activities" ? "btn-primary" : "btn-ghost"}`}
            onClick={() => setActiveTab("activities")}
            style={{ display: "flex", alignItems: "center", gap: "8px" }}
          >
            <LuTrophy size={16} /> Gamified Quests ({activities.length})
          </button>
        </div>

        {/* BRANDS & SPONSORS VIEW */}
        {activeTab === "sponsors" && (
          <div>
            {/* Search and Filters Bar */}
            <div style={{ display: "flex", flexWrap: "wrap", gap: "12px", alignItems: "center", justifyContent: "space-between", padding: "16px 20px", borderBottom: "1px solid var(--border-light)" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, minWidth: "260px" }}>
                <div style={{ position: "relative", width: "100%", maxWidth: "340px" }}>
                  <LuSearch size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "var(--text-muted)" }} />
                  <input
                    type="text"
                    className="form-input"
                    placeholder="Search sponsors by brand name or booth..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    style={{ paddingLeft: "36px" }}
                  />
                </div>
              </div>

              <div style={{ display: "flex", gap: "10px", alignItems: "center", flexWrap: "wrap" }}>
                <select 
                  className="form-select" 
                  value={tierFilter} 
                  onChange={(e) => setTierFilter(e.target.value)}
                  style={{ width: "auto", minWidth: "160px" }}
                >
                  <option value="all">All Tiers & Categories</option>
                  {SPONSOR_TIERS.map(t => (
                    <option key={t} value={t}>{t}</option>
                  ))}
                </select>

                <select 
                  className="form-select" 
                  value={locationFilter} 
                  onChange={(e) => setLocationFilter(e.target.value)}
                  style={{ width: "auto", minWidth: "170px" }}
                >
                  <option value="all">All Locations</option>
                  <option value="assigned">Venue Assigned</option>
                  <option value="unassigned">Unassigned Locations</option>
                </select>
              </div>
            </div>

            {loading ? (
              <div style={{ padding: "60px", textAlign: "center" }}><div className="spinner"></div></div>
            ) : filteredSponsors.length === 0 ? (
              <div className="empty-state" style={{ padding: "48px 24px" }}>
                <div className="empty-state-icon" style={{ background: "rgba(58, 114, 32, 0.1)", color: "var(--green-400)" }}>
                  <LuAward size={36} />
                </div>
                <div className="empty-state-title" style={{ fontSize: "1.2rem", marginTop: "12px" }}>
                  {sponsors.length === 0 ? "No brands or sponsors added yet" : "No sponsors match your filter"}
                </div>
                <div className="empty-state-text" style={{ maxWidth: "460px", margin: "8px auto 20px" }}>
                  {sponsors.length === 0 
                    ? "Add your official event sponsors and partners, specify their sponsorship tier, and assign them directly to venue zones."
                    : "Try adjusting your search keywords or filter settings."}
                </div>
                {sponsors.length === 0 && (
                  <button className="btn btn-primary" onClick={handleOpenAddSponsor}>
                    <LuPlus size={16} /> Add First Brand / Sponsor
                  </button>
                )}
              </div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th style={{ width: "260px" }}>Brand / Sponsor</th>
                      <th>Sponsorship Tier</th>
                      <th>Venue Location & Zone</th>
                      <th>Contact & Links</th>
                      <th style={{ textAlign: "right", width: "240px" }}>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredSponsors.map((s) => {
                      const tierStyle = getTierBadgeStyle(s.category);
                      const assignedZone = zones.find(z => z.id === s.zone_id)?.name || s.zone_name;
                      const hasLocation = Boolean(assignedZone || s.booth_number);

                      return (
                        <tr key={s.id}>
                          <td>
                            <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                              <div style={{ 
                                width: "38px", 
                                height: "38px", 
                                borderRadius: "8px", 
                                background: tierStyle.bg, 
                                border: tierStyle.border,
                                color: tierStyle.color,
                                display: "flex", 
                                alignItems: "center", 
                                justifyContent: "center", 
                                fontWeight: "700",
                                fontSize: "1rem"
                              }}>
                                {s.name ? s.name.charAt(0).toUpperCase() : "S"}
                              </div>
                              <div>
                                <div style={{ fontWeight: "600", color: "var(--text-primary)", fontSize: "0.95rem" }}>
                                  {s.name}
                                </div>
                                {s.company_name && s.company_name !== s.name && (
                                  <div style={{ fontSize: "0.78rem", color: "var(--text-muted)" }}>
                                    {s.company_name}
                                  </div>
                                )}
                              </div>
                            </div>
                          </td>

                          <td>
                            <span 
                              style={{ 
                                display: "inline-block", 
                                padding: "4px 10px", 
                                borderRadius: "6px", 
                                fontSize: "0.75rem", 
                                fontWeight: "700", 
                                background: tierStyle.bg, 
                                color: tierStyle.color,
                                border: tierStyle.border
                              }}
                            >
                              {s.category || "Official Sponsor"}
                            </span>
                          </td>

                          <td>
                            {hasLocation ? (
                              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                                <span style={{
                                  display: "inline-flex",
                                  alignItems: "center",
                                  gap: "6px",
                                  background: "rgba(58, 114, 32, 0.12)",
                                  color: "var(--green-400)",
                                  border: "1px solid rgba(58, 114, 32, 0.3)",
                                  padding: "4px 10px",
                                  borderRadius: "6px",
                                  fontSize: "0.82rem",
                                  fontWeight: "600"
                                }}>
                                  <LuMapPin size={13} />
                                  {assignedZone || "Zone"} {s.booth_number ? `• ${s.booth_number}` : ""}
                                </span>
                                <button
                                  className="btn btn-ghost btn-sm"
                                  onClick={() => handleOpenLocationModal(s)}
                                  title="Change assigned venue location"
                                  style={{ padding: "2px 6px", fontSize: "0.75rem", color: "var(--text-muted)" }}
                                >
                                  Change
                                </button>
                              </div>
                            ) : (
                              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                                <span style={{
                                  display: "inline-flex",
                                  alignItems: "center",
                                  gap: "5px",
                                  background: "rgba(245, 158, 11, 0.1)",
                                  color: "var(--warning)",
                                  border: "1px solid rgba(245, 158, 11, 0.3)",
                                  padding: "4px 10px",
                                  borderRadius: "6px",
                                  fontSize: "0.78rem",
                                  fontWeight: "500"
                                }}>
                                  <LuCircleAlert size={13} /> Unassigned
                                </span>
                                <button
                                  className="btn btn-secondary btn-sm"
                                  onClick={() => handleOpenLocationModal(s)}
                                  style={{ padding: "4px 10px", fontSize: "0.75rem", display: "inline-flex", alignItems: "center", gap: "4px" }}
                                >
                                  <LuMapPin size={12} /> Assign Location
                                </button>
                              </div>
                            )}
                          </td>

                          <td>
                            <div style={{ display: "flex", flexDirection: "column", gap: "2px" }}>
                              {s.website_url ? (
                                <a 
                                  href={s.website_url.startsWith("http") ? s.website_url : `https://${s.website_url}`} 
                                  target="_blank" 
                                  rel="noopener noreferrer"
                                  style={{ display: "inline-flex", alignItems: "center", gap: "4px", fontSize: "0.8rem", color: "var(--primary)" }}
                                >
                                  Website <LuExternalLink size={12} />
                                </a>
                              ) : (
                                <span style={{ fontSize: "0.78rem", color: "var(--text-muted)" }}>No website link</span>
                              )}
                              {s.contact_email && (
                                <div style={{ fontSize: "0.78rem", color: "var(--text-secondary)", display: "flex", alignItems: "center", gap: "4px" }}>
                                  <LuMail size={11} /> {s.contact_email}
                                </div>
                              )}
                            </div>
                          </td>

                          <td style={{ textAlign: "right" }}>
                            <div style={{ display: "flex", gap: "6px", justifyContent: "flex-end", alignItems: "center" }}>
                              {/* AI QUEST AGENT BUTTON */}
                              <button 
                                className="btn btn-secondary btn-sm"
                                onClick={() => handleOpenAiQuest(s)}
                                title="Build Gamified AI Quest for this brand with Gemini 3.5 Flash Lite"
                                style={{ display: "inline-flex", alignItems: "center", gap: "4px", padding: "4px 8px", fontSize: "0.75rem", color: "var(--green-400)" }}
                              >
                                <LuSparkles size={13} /> AI Quest
                              </button>

                              <button 
                                className="btn btn-ghost btn-sm" 
                                onClick={() => handleOpenLocationModal(s)}
                                title="Assign or Change Location"
                                style={{ color: "var(--text-muted)" }}
                              >
                                <LuMapPin size={14} />
                              </button>
                              <button 
                                className="btn btn-ghost btn-sm" 
                                onClick={() => handleOpenEditSponsor(s)}
                                title="Edit sponsor details"
                              >
                                <LuPencil size={14} />
                              </button>
                              <button 
                                className="btn btn-ghost btn-sm" 
                                onClick={() => handleDeleteSponsor(s.id, s.name)} 
                                style={{ color: "var(--error)" }}
                                title="Delete sponsor"
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
        )}

        {/* SESSIONS VIEW */}
        {activeTab === "sessions" && (
          <div>
            {loading ? (
              <div style={{ padding: "60px", textAlign: "center" }}><div className="spinner"></div></div>
            ) : sessions.length === 0 ? (
              <div className="empty-state" style={{ padding: "48px 24px" }}>
                <div className="empty-state-icon"><LuCalendarPlus /></div>
                <div className="empty-state-title">No sessions scheduled</div>
                <div className="empty-state-text">Schedule speaker presentations and bind them to venue zones.</div>
              </div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>Title & Speaker</th>
                      <th>Time</th>
                      <th>Mapped Zone</th>
                      <th>Location / Stage</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sessions.map(s => (
                      <tr key={s.id}>
                        <td>
                          <strong>{s.title}</strong>
                          {s.speaker_name && <div style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>By: {s.speaker_name}</div>}
                        </td>
                        <td>
                          <div style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "0.8rem" }}>
                            <LuClock size={12} /> {s.start_time || "TBD"} – {s.end_time || ""}
                          </div>
                        </td>
                        <td>
                          <span style={{ display: "inline-flex", alignItems: "center", gap: "4px", color: "var(--primary)" }}>
                            <LuMapPin size={13} /> {zones.find(z => z.id === s.zone_id)?.name || s.zone_name || "Main Stage"}
                          </span>
                        </td>
                        <td>{s.location || "Stage 1"}</td>
                        <td>
                          <div style={{ display: "flex", gap: "6px" }}>
                            <button className="btn btn-ghost btn-sm" onClick={() => { setEditingSession(s); setSessionForm(s); setIsSessionModalOpen(true); }}><LuPencil size={14} /></button>
                            <button className="btn btn-ghost btn-sm" onClick={() => handleDeleteSession(s.id)} style={{ color: "var(--error)" }}><LuTrash2 size={14} /></button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* ACTIVITIES VIEW (GAMIFIED QUESTS) */}
        {activeTab === "activities" && (
          <div>
            {loading ? (
              <div style={{ padding: "60px", textAlign: "center" }}><div className="spinner"></div></div>
            ) : activities.length === 0 ? (
              <div className="empty-state" style={{ padding: "48px 24px" }}>
                <div className="empty-state-icon"><LuTrophy /></div>
                <div className="empty-state-title">No gamified quests configured</div>
                <div className="empty-state-text">
                  Create stall-visiting quests or website-exploration challenges for your sponsors to engage attendees.
                </div>
                <div style={{ marginTop: "16px", display: "flex", gap: "10px", justifyContent: "center" }}>
                  <button className="btn btn-primary" onClick={() => handleOpenAiQuest(null)}>
                    <LuSparkles size={16} /> Generate AI Brand Quest
                  </button>
                </div>
              </div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>Quest Title & Objective</th>
                      <th>Points Reward</th>
                      <th>Target Zone / Location</th>
                      <th>Quest Type</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activities.map(a => (
                      <tr key={a.id}>
                        <td>
                          <strong style={{ fontSize: "0.95rem" }}>{a.title}</strong>
                          {a.description && <div style={{ fontSize: "0.82rem", color: "var(--text-secondary)", marginTop: "2px", maxWidth: "460px" }}>{a.description}</div>}
                        </td>
                        <td>
                          <span style={{ 
                            display: "inline-block", 
                            padding: "4px 10px", 
                            borderRadius: "6px", 
                            background: "rgba(245, 158, 11, 0.15)", 
                            color: "#FBBF24", 
                            fontWeight: "700",
                            fontSize: "0.85rem"
                          }}>
                            +{a.points_reward || a.points || 50} pts
                          </span>
                        </td>
                        <td>
                          <span style={{ display: "inline-flex", alignItems: "center", gap: "4px", color: "var(--primary)" }}>
                            <LuMapPin size={13} /> {zones.find(z => z.id === a.zone_id)?.name || a.zone_name || "Event Venue"}
                          </span>
                        </td>
                        <td>
                          <span className="badge info">
                            {a.activity_type === "scavenger" ? "Stall Visit" : a.activity_type === "game" ? "Website Exploration" : a.activity_type}
                          </span>
                        </td>
                        <td>
                          <div style={{ display: "flex", gap: "6px", alignItems: "center" }}>
                            <button 
                              className="btn btn-sm btn-primary" 
                              onClick={() => handleOpenBroadcastModal(a)}
                              title="Send / Broadcast this gamified quest to all attendees or a specific zone"
                              style={{ display: "flex", alignItems: "center", gap: "5px", fontSize: "0.78rem", padding: "4px 10px" }}
                            >
                              <LuSend size={13} /> Send Quest
                            </button>
                            <button className="btn btn-ghost btn-sm" onClick={() => { setEditingActivity(a); setActivityForm(a); setIsActivityModalOpen(true); }}><LuPencil size={14} /></button>
                            <button className="btn btn-ghost btn-sm" onClick={() => handleDeleteActivity(a.id)} style={{ color: "var(--error)" }}><LuTrash2 size={14} /></button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>

      {/* AI QUEST GENERATOR AGENT MODAL (POWERED BY GEMINI 3.5 FLASH LITE) */}
      {isAiQuestModalOpen && (
        <div className="modal-overlay fade-in" onClick={() => setIsAiQuestModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "600px", maxHeight: "90vh", overflowY: "auto" }}>
            <div className="modal-header">
              <div>
                <h3 style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "1.15rem" }}>
                  <LuSparkles color="var(--green-400)" size={22} /> AI Gamified Quest Generator
                </h3>
                <div style={{ display: "flex", alignItems: "center", gap: "6px", marginTop: "2px" }}>
                  <span style={{ fontSize: "0.75rem", color: "var(--text-muted)" }}>Agent Model:</span>
                  <span className="badge" style={{ background: "rgba(58, 114, 32, 0.2)", color: "var(--green-300)", fontSize: "0.7rem", padding: "1px 6px" }}>
                    Gemini 3.5 Flash Lite
                  </span>
                </div>
              </div>
              <button 
                className="btn-icon" 
                onClick={() => setIsAiQuestModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>

            <div className="modal-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
              <p style={{ color: "var(--text-secondary)", fontSize: "0.85rem", margin: 0 }}>
                The AI Agent will craft a custom gamified quest. If the brand has an exhibition stall, attendees must visit the stall in-person to earn points. If not, attendees explore the sponsor's website online for 3-5 minutes.
              </p>

              {/* Brand Name Input / Select */}
              <div className="form-group">
                <label className="form-label">Brand / Sponsor Name *</label>
                <div style={{ display: "flex", gap: "8px" }}>
                  <input 
                    type="text" 
                    className="form-input" 
                    placeholder="e.g. Nike, Red Bull, Spotify, Intel"
                    value={aiQuestInput.brand_name}
                    onChange={(e) => setAiQuestInput({ ...aiQuestInput, brand_name: e.target.value })}
                  />
                  {sponsors.length > 0 && (
                    <select
                      className="form-select"
                      style={{ width: "auto", minWidth: "140px" }}
                      value=""
                      onChange={(e) => {
                        const found = sponsors.find(s => s.id === e.target.value);
                        if (found) {
                          setAiQuestInput({
                            brand_name: found.name,
                            has_stall: Boolean(found.zone_id || found.booth_number),
                            zone_id: found.zone_id || "",
                            booth_number: found.booth_number || "",
                            website_url: found.website_url || "",
                            category: found.category || "Official Sponsor",
                            points_tier: 100,
                          });
                        }
                      }}
                    >
                      <option value="">Pick from list...</option>
                      {sponsors.map(s => (
                        <option key={s.id} value={s.id}>{s.name}</option>
                      ))}
                    </select>
                  )}
                </div>
              </div>

              {/* Stall vs Digital Sponsor Toggle */}
              <div className="form-group">
                <label className="form-label" style={{ marginBottom: "8px" }}>Exhibition Presence *</label>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <div 
                    onClick={() => setAiQuestInput({ ...aiQuestInput, has_stall: true })}
                    style={{
                      padding: "12px 14px",
                      borderRadius: "8px",
                      border: aiQuestInput.has_stall ? "2px solid var(--green-400)" : "1px solid var(--border-default)",
                      background: aiQuestInput.has_stall ? "rgba(58, 114, 32, 0.12)" : "var(--bg-tertiary)",
                      cursor: "pointer",
                      transition: "all 0.15s ease"
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600", fontSize: "0.9rem", color: aiQuestInput.has_stall ? "var(--green-400)" : "var(--text-primary)" }}>
                      <LuStore size={18} /> Has Physical Stall
                    </div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "4px" }}>
                      Quest: Walk to the stall, see demo, scan booth checkpoint.
                    </div>
                  </div>

                  <div 
                    onClick={() => setAiQuestInput({ ...aiQuestInput, has_stall: false })}
                    style={{
                      padding: "12px 14px",
                      borderRadius: "8px",
                      border: !aiQuestInput.has_stall ? "2px solid #38BDF8" : "1px solid var(--border-default)",
                      background: !aiQuestInput.has_stall ? "rgba(56, 189, 248, 0.12)" : "var(--bg-tertiary)",
                      cursor: "pointer",
                      transition: "all 0.15s ease"
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600", fontSize: "0.9rem", color: !aiQuestInput.has_stall ? "#38BDF8" : "var(--text-primary)" }}>
                      <LuGlobe size={18} /> Digital Sponsor (No Stall)
                    </div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "4px" }}>
                      Quest: Visit sponsor website for 3-5 mins, answer trivia/claim code.
                    </div>
                  </div>
                </div>
              </div>

              {/* Conditional Location or Website fields */}
              {aiQuestInput.has_stall ? (
                <div style={{ background: "rgba(58, 114, 32, 0.08)", padding: "12px 14px", borderRadius: "8px", border: "1px solid rgba(58, 114, 32, 0.2)" }}>
                  <div style={{ fontSize: "0.8rem", fontWeight: "600", color: "var(--green-400)", marginBottom: "8px", display: "flex", alignItems: "center", gap: "6px" }}>
                    <LuMapPin size={14} /> Physical Venue Stall Location
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                    <div>
                      <label className="form-label" style={{ fontSize: "0.75rem" }}>Venue Zone</label>
                      <select 
                        className="form-select"
                        value={aiQuestInput.zone_id}
                        onChange={(e) => setAiQuestInput({ ...aiQuestInput, zone_id: e.target.value })}
                      >
                        <option value="">-- Choose Zone --</option>
                        {zones.map(z => (
                          <option key={z.id} value={z.id}>{z.name}</option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="form-label" style={{ fontSize: "0.75rem" }}>Booth Code / Spot</label>
                      <input 
                        type="text" 
                        className="form-input" 
                        placeholder="e.g. Booth #S-12"
                        value={aiQuestInput.booth_number}
                        onChange={(e) => setAiQuestInput({ ...aiQuestInput, booth_number: e.target.value })}
                      />
                    </div>
                  </div>
                </div>
              ) : (
                <div style={{ background: "rgba(56, 189, 248, 0.08)", padding: "12px 14px", borderRadius: "8px", border: "1px solid rgba(56, 189, 248, 0.2)" }}>
                  <div style={{ fontSize: "0.8rem", fontWeight: "600", color: "#38BDF8", marginBottom: "8px", display: "flex", alignItems: "center", gap: "6px" }}>
                    <LuGlobe size={14} /> Digital Sponsor Web Address
                  </div>
                  <div>
                    <label className="form-label" style={{ fontSize: "0.75rem" }}>Official Website URL</label>
                    <input 
                      type="url" 
                      className="form-input" 
                      placeholder="e.g. https://www.nike.com"
                      value={aiQuestInput.website_url}
                      onChange={(e) => setAiQuestInput({ ...aiQuestInput, website_url: e.target.value })}
                    />
                  </div>
                </div>
              )}

              {/* Points Tier Selector */}
              <div className="form-group">
                <label className="form-label">Points Reward</label>
                <div style={{ display: "flex", gap: "8px" }}>
                  {[50, 100, 150].map(pts => (
                    <button
                      key={pts}
                      type="button"
                      className={`btn btn-sm ${Number(aiQuestInput.points_tier) === pts ? "btn-primary" : "btn-ghost"}`}
                      onClick={() => setAiQuestInput({ ...aiQuestInput, points_tier: pts })}
                      style={{ flex: 1, padding: "8px" }}
                    >
                      +{pts} pts {pts === 50 ? "(Quick)" : pts === 100 ? "(Standard)" : "(Featured)"}
                    </button>
                  ))}
                </div>
              </div>

              {/* Generate Button */}
              <button
                type="button"
                className="btn btn-primary"
                onClick={handleGenerateAiQuest}
                disabled={aiQuestLoading || !aiQuestInput.brand_name.trim()}
                style={{ padding: "12px", display: "flex", alignItems: "center", justifyContent: "center", gap: "8px" }}
              >
                {aiQuestLoading ? (
                  <>
                    <div className="spinner spinner-sm"></div> Gemini 3.5 Flash Lite is crafting quest...
                  </>
                ) : (
                  <>
                    <LuSparkles size={16} /> Generate Gamified Quest with Gemini
                  </>
                )}
              </button>

              {/* AI GENERATED RESULT PREVIEW CARD */}
              {generatedQuest && (
                <div className="fade-in" style={{
                  background: "var(--bg-tertiary)",
                  border: "1px solid var(--border-default)",
                  borderRadius: "10px",
                  padding: "16px",
                  marginTop: "8px"
                }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px" }}>
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                      <span className="badge" style={{
                        background: generatedQuest.quest_type === "stall_visit" ? "rgba(58, 114, 32, 0.2)" : "rgba(56, 189, 248, 0.2)",
                        color: generatedQuest.quest_type === "stall_visit" ? "var(--green-300)" : "#7DD3FC",
                        fontWeight: "700"
                      }}>
                        {generatedQuest.quest_type === "stall_visit" ? "🏬 Physical Stall Visit" : "🌐 Website Exploration"}
                      </span>
                      <span className="badge" style={{ background: "rgba(245, 158, 11, 0.15)", color: "#FBBF24" }}>
                        +{generatedQuest.points_reward} Points
                      </span>
                    </div>

                    <span style={{ fontSize: "0.72rem", color: "var(--text-muted)" }}>
                      {generatedQuest.model_used || "gemini-3.5-flash-lite"}
                    </span>
                  </div>

                  <div className="form-group" style={{ marginBottom: "10px" }}>
                    <label className="form-label" style={{ fontSize: "0.75rem" }}>Quest Title</label>
                    <input 
                      type="text" 
                      className="form-input" 
                      value={generatedQuest.title}
                      onChange={(e) => setGeneratedQuest({ ...generatedQuest, title: e.target.value })}
                    />
                  </div>

                  <div className="form-group" style={{ marginBottom: "10px" }}>
                    <label className="form-label" style={{ fontSize: "0.75rem" }}>Attendee Instructions & Clue</label>
                    <textarea 
                      className="form-textarea" 
                      rows={3}
                      value={generatedQuest.description}
                      onChange={(e) => setGeneratedQuest({ ...generatedQuest, description: e.target.value })}
                    />
                  </div>

                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px", fontSize: "0.78rem", color: "var(--text-secondary)", marginBottom: "12px", background: "var(--bg-secondary)", padding: "10px", borderRadius: "6px" }}>
                    <div>
                      <strong>Verification:</strong> {generatedQuest.verification_method || "Checkpoint scan / Web browse"}
                    </div>
                    <div>
                      <strong>Est. Time:</strong> ~{generatedQuest.estimated_minutes || 5} minutes
                    </div>
                    {generatedQuest.target_url && (
                      <div style={{ gridColumn: "1 / -1", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                        <strong>URL:</strong> <a href={generatedQuest.target_url} target="_blank" rel="noopener noreferrer" style={{ color: "var(--primary)" }}>{generatedQuest.target_url}</a>
                      </div>
                    )}
                    {generatedQuest.target_location && (
                      <div style={{ gridColumn: "1 / -1" }}>
                        <strong>Location:</strong> {generatedQuest.target_location}
                      </div>
                    )}
                  </div>

                  {generatedQuest.trivia_or_clue && (
                    <div style={{ fontSize: "0.78rem", color: "var(--text-muted)", fontStyle: "italic", marginBottom: "14px" }}>
                      💡 {generatedQuest.trivia_or_clue}
                    </div>
                  )}

                  <div style={{ display: "flex", gap: "8px", justifyContent: "flex-end" }}>
                    <button
                      type="button"
                      className="btn btn-ghost btn-sm"
                      onClick={handleGenerateAiQuest}
                      disabled={aiQuestLoading}
                    >
                      <LuSparkles size={13} /> Regenerate
                    </button>
                    <button
                      type="button"
                      className="btn btn-primary btn-sm"
                      onClick={handleSaveGeneratedQuest}
                      disabled={aiQuestSaving}
                      style={{ display: "flex", alignItems: "center", gap: "6px" }}
                    >
                      {aiQuestSaving ? (
                        <>
                          <div className="spinner spinner-sm"></div> Saving...
                        </>
                      ) : (
                        <>
                          <LuCheck size={14} /> Save to Event Quests
                        </>
                      )}
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ADD / EDIT BRAND & SPONSOR MODAL */}
      {isSponsorModalOpen && (
        <div className="modal-overlay fade-in" onClick={() => setIsSponsorModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "540px", maxHeight: "90vh", overflowY: "auto" }}>
            <div className="modal-header">
              <h3 style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "1.1rem" }}>
                <LuAward color="var(--green-400)" size={20} />
                {editingSponsor ? "Edit Brand / Sponsor" : "Add Brand / Sponsor"}
              </h3>
              <button 
                className="btn-icon" 
                onClick={() => setIsSponsorModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveSponsor}>
              <div className="modal-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                <div className="form-group">
                  <label className="form-label">Brand / Sponsor Name *</label>
                  <input 
                    type="text" 
                    className="form-input" 
                    placeholder="e.g. Red Bull, Google Cloud, Nike"
                    value={sponsorForm.name} 
                    onChange={e => setSponsorForm({...sponsorForm, name: e.target.value})} 
                    required 
                  />
                </div>

                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                  <div className="form-group">
                    <label className="form-label">Legal / Company Name</label>
                    <input 
                      type="text" 
                      className="form-input" 
                      placeholder="e.g. Red Bull GmbH"
                      value={sponsorForm.company_name} 
                      onChange={e => setSponsorForm({...sponsorForm, company_name: e.target.value})} 
                    />
                  </div>

                  <div className="form-group">
                    <label className="form-label">Sponsorship Tier *</label>
                    <select 
                      className="form-select" 
                      value={sponsorForm.category} 
                      onChange={e => setSponsorForm({...sponsorForm, category: e.target.value})}
                    >
                      {SPONSOR_TIERS.map(t => (
                        <option key={t} value={t}>{t}</option>
                      ))}
                    </select>
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label">Description / Activation Bio</label>
                  <textarea 
                    className="form-textarea" 
                    rows={2}
                    placeholder="Brief description of the sponsor showcase, product giveaways, or booth..."
                    value={sponsorForm.description} 
                    onChange={e => setSponsorForm({...sponsorForm, description: e.target.value})} 
                  />
                </div>

                {/* VENUE LOCATION ASSIGNMENT SECTION */}
                <div style={{ background: "var(--bg-tertiary)", padding: "14px", borderRadius: "10px", border: "1px solid var(--border-light)" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "0.85rem", fontWeight: "600", color: "var(--green-400)", marginBottom: "10px" }}>
                    <LuMapPin size={16} /> Venue Location Assignment
                  </div>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                    <div className="form-group" style={{ marginBottom: 0 }}>
                      <label className="form-label" style={{ fontSize: "0.78rem" }}>Venue Zone</label>
                      <select 
                        className="form-select" 
                        value={sponsorForm.zone_id} 
                        onChange={e => setSponsorForm({...sponsorForm, zone_id: e.target.value})}
                      >
                        <option value="">-- Choose Zone --</option>
                        {zones.map(z => (
                          <option key={z.id} value={z.id}>{z.name} (Floor {z.floor_level || 1})</option>
                        ))}
                      </select>
                    </div>

                    <div className="form-group" style={{ marginBottom: 0 }}>
                      <label className="form-label" style={{ fontSize: "0.78rem" }}>Booth / Location Spot</label>
                      <input 
                        type="text" 
                        className="form-input" 
                        value={sponsorForm.booth_number} 
                        onChange={e => setSponsorForm({...sponsorForm, booth_number: e.target.value})} 
                        placeholder="e.g. Booth S-12, Pavilion A" 
                      />
                    </div>
                  </div>
                </div>

                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                  <div className="form-group">
                    <label className="form-label">Official Website URL</label>
                    <input 
                      type="url" 
                      className="form-input" 
                      placeholder="https://sponsor.com"
                      value={sponsorForm.website_url} 
                      onChange={e => setSponsorForm({...sponsorForm, website_url: e.target.value})} 
                    />
                  </div>

                  <div className="form-group">
                    <label className="form-label">Contact Email</label>
                    <input 
                      type="email" 
                      className="form-input" 
                      placeholder="partner@sponsor.com"
                      value={sponsorForm.contact_email} 
                      onChange={e => setSponsorForm({...sponsorForm, contact_email: e.target.value})} 
                    />
                  </div>
                </div>
              </div>

              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setIsSponsorModalOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary">
                  {editingSponsor ? "Save Changes" : "Create Brand / Sponsor"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* QUICK ASSIGN VENUE LOCATION MODAL */}
      {isLocationModalOpen && locatingSponsor && (
        <div className="modal-overlay fade-in" onClick={() => setIsLocationModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "460px" }}>
            <div className="modal-header">
              <h3 style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "1.1rem" }}>
                <LuMapPin color="var(--green-400)" size={20} /> Assign Venue Location
              </h3>
              <button 
                className="btn-icon" 
                onClick={() => setIsLocationModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveLocation}>
              <div className="modal-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                <div style={{ background: "var(--bg-tertiary)", padding: "12px 16px", borderRadius: "8px", border: "1px solid var(--border-light)" }}>
                  <div style={{ fontSize: "0.8rem", color: "var(--text-muted)", textTransform: "uppercase", fontWeight: "600" }}>
                    Selected Brand / Sponsor
                  </div>
                  <div style={{ fontSize: "1.1rem", fontWeight: "700", color: "var(--text-primary)", marginTop: "2px" }}>
                    {locatingSponsor.name}
                  </div>
                  <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "2px" }}>
                    Tier: {locatingSponsor.category || "Official Partner"}
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label">Venue Zone *</label>
                  <select 
                    className="form-select" 
                    value={locationForm.zone_id} 
                    onChange={e => setLocationForm({...locationForm, zone_id: e.target.value})}
                  >
                    <option value="">-- Select Venue Zone --</option>
                    {zones.map(z => (
                      <option key={z.id} value={z.id}>
                        {z.name} (Floor {z.floor_level || 1})
                      </option>
                    ))}
                  </select>
                  <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", marginTop: "4px" }}>
                    Select which physical area of the venue this sponsor will occupy.
                  </p>
                </div>

                <div className="form-group">
                  <label className="form-label">Booth / Stall / Location Spot Identifier</label>
                  <input 
                    type="text" 
                    className="form-input" 
                    placeholder="e.g. Booth S-10, Main Hall Canopy 4"
                    value={locationForm.booth_number} 
                    onChange={e => setLocationForm({...locationForm, booth_number: e.target.value})} 
                  />
                  <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", marginTop: "4px" }}>
                    The specific booth or booth number attendees can look for.
                  </p>
                </div>
              </div>

              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setIsLocationModalOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary" style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                  <LuCircleCheck size={16} /> Save Venue Location
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* SESSION MODAL */}
      {isSessionModalOpen && (
        <div className="modal-overlay fade-in" onClick={() => setIsSessionModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "480px" }}>
            <div className="modal-header">
              <h3 style={{ fontSize: "1.1rem" }}>{editingSession ? "Edit Session" : "Schedule Presentation Session"}</h3>
              <button 
                className="btn-icon" 
                onClick={() => setIsSessionModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>
            <div className="modal-body">
              <form onSubmit={handleSaveSession} style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                <div className="form-group">
                  <label className="form-label">Session Title *</label>
                  <input type="text" className="form-input" value={sessionForm.title} onChange={e => setSessionForm({...sessionForm, title: e.target.value})} required />
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <div className="form-group">
                    <label className="form-label">Speaker Name</label>
                    <input type="text" className="form-input" value={sessionForm.speaker_name} onChange={e => setSessionForm({...sessionForm, speaker_name: e.target.value})} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Mapped Zone</label>
                    <select className="form-select" value={sessionForm.zone_id} onChange={e => setSessionForm({...sessionForm, zone_id: e.target.value})}>
                      <option value="">-- Select Zone --</option>
                      {zones.map(z => <option key={z.id} value={z.id}>{z.name}</option>)}
                    </select>
                  </div>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <div className="form-group">
                    <label className="form-label">Start Time</label>
                    <input type="time" className="form-input" value={sessionForm.start_time} onChange={e => setSessionForm({...sessionForm, start_time: e.target.value})} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">End Time</label>
                    <input type="time" className="form-input" value={sessionForm.end_time} onChange={e => setSessionForm({...sessionForm, end_time: e.target.value})} />
                  </div>
                </div>
                <div className="modal-footer" style={{ padding: "16px 0 0", marginTop: "12px" }}>
                  <button type="button" className="btn btn-ghost" onClick={() => setIsSessionModalOpen(false)}>Cancel</button>
                  <button type="submit" className="btn btn-primary">Save Session</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* ACTIVITY MODAL */}
      {isActivityModalOpen && (
        <div className="modal-overlay fade-in" onClick={() => setIsActivityModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "460px" }}>
            <div className="modal-header">
              <h3 style={{ fontSize: "1.1rem" }}>{editingActivity ? "Edit Quest" : "Create Gamified Quest"}</h3>
              <button 
                className="btn-icon" 
                onClick={() => setIsActivityModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>
            <div className="modal-body">
              <form onSubmit={handleSaveActivity} style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                <div className="form-group">
                  <label className="form-label">Quest Title *</label>
                  <input type="text" className="form-input" value={activityForm.title} onChange={e => setActivityForm({...activityForm, title: e.target.value})} required />
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <div className="form-group">
                    <label className="form-label">Points Reward</label>
                    <input type="number" className="form-input" value={activityForm.points_reward} onChange={e => setActivityForm({...activityForm, points_reward: e.target.value})} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Target Zone</label>
                    <select className="form-select" value={activityForm.zone_id} onChange={e => setActivityForm({...activityForm, zone_id: e.target.value})}>
                      <option value="">-- Any Zone --</option>
                      {zones.map(z => <option key={z.id} value={z.id}>{z.name}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Description & Clue</label>
                  <textarea className="form-textarea" placeholder="Describe the quest clue or task..." value={activityForm.description} onChange={e => setActivityForm({...activityForm, description: e.target.value})} />
                </div>
                <div className="modal-footer" style={{ padding: "16px 0 0", marginTop: "12px" }}>
                  <button type="button" className="btn btn-ghost" onClick={() => setIsActivityModalOpen(false)}>Cancel</button>
                  <button type="submit" className="btn btn-primary">Save Quest</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* BROADCAST QUEST MODAL */}
      {isBroadcastModalOpen && broadcastingQuest && (
        <div className="modal-overlay fade-in" onClick={() => setIsBroadcastModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: "520px" }}>
            <div className="modal-header">
              <h3 style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "1.1rem" }}>
                <LuSend color="var(--primary)" size={20} /> Send Gamified Quest
              </h3>
              <button 
                className="btn-icon" 
                onClick={() => setIsBroadcastModalOpen(false)}
                style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer" }}
              >
                <LuX size={20} />
              </button>
            </div>

            <div className="modal-body">
              <form onSubmit={handleSendQuestBroadcast} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                {/* Selected Quest Summary Card */}
                <div style={{
                  background: "var(--bg-tertiary)",
                  border: "1px solid var(--border-default)",
                  borderRadius: "8px",
                  padding: "12px 14px",
                }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "8px" }}>
                    <div>
                      <strong style={{ fontSize: "0.95rem", color: "var(--text-primary)" }}>{broadcastingQuest.title}</strong>
                      <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginTop: "4px" }}>
                        {broadcastingQuest.description || "Interactive attendee challenge."}
                      </div>
                    </div>
                    <span style={{ 
                      padding: "3px 8px", 
                      borderRadius: "6px", 
                      background: "rgba(245, 158, 11, 0.15)", 
                      color: "#FBBF24", 
                      fontWeight: "700",
                      fontSize: "0.8rem",
                      whiteSpace: "nowrap"
                    }}>
                      +{broadcastingQuest.points_reward || broadcastingQuest.points || 50} pts
                    </span>
                  </div>
                </div>

                {/* Target Audience Selection */}
                <div className="form-group">
                  <label className="form-label" style={{ fontWeight: "600" }}>Target Audience</label>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginTop: "4px" }}>
                    <div 
                      onClick={() => setBroadcastTarget("all")}
                      style={{
                        padding: "12px",
                        borderRadius: "8px",
                        border: broadcastTarget === "all" ? "2px solid var(--primary)" : "1px solid var(--border-default)",
                        background: broadcastTarget === "all" ? "rgba(99, 102, 241, 0.1)" : "var(--bg-secondary)",
                        cursor: "pointer",
                        transition: "all 0.2s ease"
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600", fontSize: "0.9rem" }}>
                        <input 
                          type="radio" 
                          checked={broadcastTarget === "all"} 
                          onChange={() => setBroadcastTarget("all")} 
                          style={{ accentColor: "var(--primary)" }}
                        />
                        <span>All Attendees</span>
                      </div>
                      <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "4px", paddingLeft: "24px" }}>
                        Sends in-app popup and push alert to everyone at the event.
                      </div>
                    </div>

                    <div 
                      onClick={() => setBroadcastTarget("zone")}
                      style={{
                        padding: "12px",
                        borderRadius: "8px",
                        border: broadcastTarget === "zone" ? "2px solid var(--primary)" : "1px solid var(--border-default)",
                        background: broadcastTarget === "zone" ? "rgba(99, 102, 241, 0.1)" : "var(--bg-secondary)",
                        cursor: "pointer",
                        transition: "all 0.2s ease"
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px", fontWeight: "600", fontSize: "0.9rem" }}>
                        <input 
                          type="radio" 
                          checked={broadcastTarget === "zone"} 
                          onChange={() => setBroadcastTarget("zone")} 
                          style={{ accentColor: "var(--primary)" }}
                        />
                        <span>Specific Zone</span>
                      </div>
                      <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: "4px", paddingLeft: "24px" }}>
                        Only alerts attendees currently localized in that event zone.
                      </div>
                    </div>
                  </div>
                </div>

                {/* Zone Picker if "Specific Zone" is selected */}
                {broadcastTarget === "zone" && (
                  <div className="form-group fade-in">
                    <label className="form-label" style={{ fontWeight: "600" }}>Select Event Zone *</label>
                    <select 
                      className="form-select" 
                      value={broadcastZoneId} 
                      onChange={e => setBroadcastZoneId(e.target.value)}
                      required
                    >
                      <option value="">-- Choose Target Zone --</option>
                      {zones.map(z => (
                        <option key={z.id} value={z.id}>
                          {z.name} {z.code ? `(${z.code})` : ""}
                        </option>
                      ))}
                    </select>
                    <span style={{ fontSize: "0.74rem", color: "var(--text-muted)", marginTop: "4px", display: "block" }}>
                      Spatially's BLE proximity and zone radar will deliver this alert only to phones detected in this sector.
                    </span>
                  </div>
                )}

                <div className="modal-footer" style={{ padding: "16px 0 0", marginTop: "8px", display: "flex", justifyContent: "flex-end", gap: "10px" }}>
                  <button type="button" className="btn btn-ghost" onClick={() => setIsBroadcastModalOpen(false)}>
                    Cancel
                  </button>
                  <button 
                    type="submit" 
                    className="btn btn-primary"
                    disabled={broadcastSending || (broadcastTarget === "zone" && !broadcastZoneId)}
                    style={{ display: "flex", alignItems: "center", gap: "6px" }}
                  >
                    {broadcastSending ? (
                      <>
                        <div className="spinner spinner-sm"></div> Sending...
                      </>
                    ) : (
                      <>
                        <LuSend size={15} /> Send Quest Now
                      </>
                    )}
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}