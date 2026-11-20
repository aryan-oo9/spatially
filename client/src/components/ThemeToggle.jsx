import { LuSun, LuMoon } from "react-icons/lu";
import { useTheme } from "../context/ThemeContext";

export default function ThemeToggle({ className = "", showLabel = false }) {
  const { theme: _theme, toggleTheme, isDark } = useTheme();

  return (
    <button
      type="button"
      className={`theme-toggle-btn ${className}`}
      onClick={toggleTheme}
      aria-label={`Switch to ${isDark ? "light" : "dark"} mode`}
      title={`Switch to ${isDark ? "light" : "dark"} mode`}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "8px",
        padding: "6px 12px",
        borderRadius: "var(--radius-full)",
        border: "1px solid var(--border-default)",
        backgroundColor: "var(--bg-tertiary)",
        color: "var(--text-primary)",
        cursor: "pointer",
        transition: "all var(--transition-fast)",
        fontSize: "0.825rem",
        fontWeight: "600",
        userSelect: "none",
        outline: "none",
      }}
    >
      <span
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: "20px",
          height: "20px",
          borderRadius: "50%",
          backgroundColor: isDark ? "rgba(234, 179, 8, 0.15)" : "rgba(46, 125, 50, 0.15)",
          color: isDark ? "#FACC15" : "var(--green-600)",
          transition: "transform 0.3s ease, background-color 0.3s ease",
          transform: isDark ? "rotate(0deg)" : "rotate(360deg)",
        }}
      >
        {isDark ? <LuSun size={14} /> : <LuMoon size={14} />}
      </span>
      {showLabel ? (
        <span>{isDark ? "Light Mode" : "Dark Mode"}</span>
      ) : (
        <span style={{ fontSize: "0.78rem", color: "var(--text-secondary)", fontWeight: 600 }}>
          {isDark ? "Light" : "Dark"}
        </span>
      )}
    </button>
  );
}
