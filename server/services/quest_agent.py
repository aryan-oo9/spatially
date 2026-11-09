import os
import json
import logging
import httpx
from typing import Dict, Any, Optional

logger = logging.getLogger("spatially.quest_agent")

MODELS_FALLBACK_LIST = [
    "gemini-3.5-flash-lite",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash-lite",
    "gemini-1.5-flash",
]

def generate_fallback_quest(
    brand_name: str,
    has_stall: bool,
    zone_name: Optional[str] = None,
    booth_number: Optional[str] = None,
    website_url: Optional[str] = None,
    category: Optional[str] = None,
    points_tier: int = 100
) -> Dict[str, Any]:
    """Generates an intelligent context-aware quest when API is offline or key is unconfigured."""
    b_name = brand_name.strip() if brand_name else "Brand Partner"
    tier_label = category or "Sponsor"

    if has_stall:
        loc_str = ""
        if zone_name and booth_number:
            loc_str = f"at {booth_number} in {zone_name}"
        elif zone_name:
            loc_str = f"in {zone_name}"
        elif booth_number:
            loc_str = f"at {booth_number}"
        else:
            loc_str = "at their physical exhibition stall"

        title = f"{b_name} Explorer: Visit the Booth"
        description = (
            f"Head over to the {b_name} exhibition stall {loc_str}. "
            f"Check out their latest showcase, talk with the team, and scan the checkpoint QR code "
            f"to unlock your exclusive {points_tier} event points!"
        )
        return {
            "title": title,
            "description": description,
            "quest_type": "stall_visit",
            "activity_type": "scavenger",
            "points_reward": points_tier,
            "call_to_action": f"Navigate to {b_name} Stall",
            "verification_method": "Scan Booth QR Checkpoint",
            "target_url": website_url or None,
            "target_location": loc_str,
            "estimated_minutes": 5,
            "trivia_or_clue": f"Ask the staff at {b_name} about their featured flagship giveaway!",
            "ai_generated": False,
            "model_used": "spatially-heuristic-engine"
        }
    else:
        url_display = website_url or f"https://www.{b_name.lower().replace(' ', '')}.com"
        title = f"{b_name} Digital Discovery: 5-Minute Deep Dive"
        description = (
            f"As our official {tier_label}, {b_name} is powering this event digitally! "
            f"Explore their official portal at {url_display} for 3 to 5 minutes, "
            f"discover their featured showcase, and claim your {points_tier} reward points."
        )
        return {
            "title": title,
            "description": description,
            "quest_type": "website_visit",
            "activity_type": "game",
            "points_reward": points_tier,
            "call_to_action": f"Open {b_name} Website",
            "verification_method": "Browse Website & Claim Digital Voucher",
            "target_url": url_display,
            "target_location": "Online / Digital Activation",
            "estimated_minutes": 5,
            "trivia_or_clue": f"Discover what makes {b_name} a leading pioneer in their space on their homepage.",
            "ai_generated": False,
            "model_used": "spatially-heuristic-engine"
        }


async def generate_brand_quest(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    AI Agent that generates tailored gamified quests for a brand/sponsor using Gemini 3.5 Flash Lite.
    Adapts based on whether the brand has a physical stall or is a digital sponsor.
    """
    brand_name = data.get("brand_name") or data.get("name") or "Brand"
    has_stall = bool(data.get("has_stall", False))
    zone_name = data.get("zone_name")
    booth_number = data.get("booth_number")
    website_url = data.get("website_url")
    category = data.get("category") or "Official Sponsor"
    points_tier = int(data.get("points_tier") or data.get("points") or 100)
    event_name = data.get("event_name") or "the event"

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        logger.info("GEMINI_API_KEY not configured. Using Spatially intelligent quest generator.")
        fallback = generate_fallback_quest(
            brand_name, has_stall, zone_name, booth_number, website_url, category, points_tier
        )
        fallback["note"] = "Generated with built-in heuristic agent (GEMINI_API_KEY not set)."
        return fallback

    # Prepare prompt for Gemini AI Agent
    if has_stall:
        scenario = (
            f"The brand '{brand_name}' HAS A PHYSICAL EXHIBITION STALL at {event_name}.\n"
            f"- Zone / Area: {zone_name or 'Main Exhibition Hall'}\n"
            f"- Booth / Stall Code: {booth_number or 'Booth Area'}\n"
            f"- Tier: {category}\n"
            f"TASK: Generate a PHYSICAL STALL VISIT quest. The attendee must physically walk to this booth, "
            f"experience the brand's demo/products, and verify their visit by scanning a QR checkpoint to earn {points_tier} points."
        )
    else:
        scenario = (
            f"The brand '{brand_name}' DOES NOT HAVE A PHYSICAL STALL. They are a headline / digital sponsor at {event_name}.\n"
            f"- Website: {website_url or 'Official Website'}\n"
            f"- Tier: {category}\n"
            f"TASK: Generate a DIGITAL / WEBSITE DISCOVERY quest. Since there is no stall at the venue, the attendee "
            f"must visit the sponsor's website ({website_url or 'website'}), spend ~5 minutes exploring their featured products, "
            f"brand story, or event campaign, and claim {points_tier} points."
        )

    prompt = f"""You are the Gamification Experience AI Agent for Spatially, an intelligent spatial event operating system.
Generate an exciting, high-engagement gamified attendee quest based on this brand scenario:

{scenario}

REQUIREMENTS:
1. If has_stall is true: Quest type MUST be 'stall_visit', activity_type MUST be 'scavenger'. Description must direct attendee to the physical zone/stall.
2. If has_stall is false: Quest type MUST be 'website_visit', activity_type MUST be 'game'. Description must prompt attendee to explore the website for ~5 mins.
3. Be enthusiastic, modern, and engaging.
4. Output ONLY valid, raw JSON with NO markdown code fences or backticks.

JSON SCHEMA:
{{
  "title": "Catchy quest title (e.g. '{brand_name} Speed Challenge: Visit Stall {booth_number or 'A-1'}' or 'Discover {brand_name} Innovation on the Web')",
  "description": "2-3 sentences of clear attendee instructions with context and energy",
  "quest_type": "{'stall_visit' if has_stall else 'website_visit'}",
  "activity_type": "{'scavenger' if has_stall else 'game'}",
  "points_reward": {points_tier},
  "call_to_action": "{'Navigate to Stall' if has_stall else 'Visit Website & Explore'}",
  "verification_method": "{'Scan Booth QR Checkpoint' if has_stall else '5-Minute Website Timer & Verification Code'}",
  "target_url": "{website_url or ''}",
  "target_location": "{f'{zone_name} • {booth_number}' if (zone_name or booth_number) else ('Physical Booth' if has_stall else 'Digital Sponsor')}",
  "estimated_minutes": 5,
  "trivia_or_clue": "A short, exciting trivia or clue related to {brand_name}"
}}"""

    # Model resolution with fallback list
    requested_model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite")
    models_to_try = [requested_model] + [m for m in MODELS_FALLBACK_LIST if m != requested_model]

    async with httpx.AsyncClient(timeout=15.0) as client:
        last_error = None
        for model in models_to_try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            payload = {
                "contents": [
                    {
                        "parts": [
                            {"text": prompt}
                        ]
                    }
                ],
                "generationConfig": {
                    "temperature": 0.7,
                    "maxOutputTokens": 600,
                    "responseMimeType": "application/json"
                }
            }

            try:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    data = response.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        text = candidates[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                        # Parse JSON
                        cleaned_text = text.strip()
                        if cleaned_text.startswith("```"):
                            lines = cleaned_text.split("\n")
                            cleaned_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
                        parsed = json.loads(cleaned_text)
                        parsed["ai_generated"] = True
                        parsed["model_used"] = model
                        return parsed
                elif response.status_code in (404, 400):
                    last_error = f"Model {model} returned {response.status_code}: {response.text}"
                    logger.warning(f"Gemini model {model} not found or invalid ({response.status_code}), trying next fallback...")
                    continue
                else:
                    last_error = f"Gemini API returned status {response.status_code}: {response.text}"
                    break
            except Exception as e:
                last_error = str(e)
                logger.warning(f"Error calling model {model}: {e}")
                continue

    logger.warning(f"All Gemini models failed ({last_error}). Falling back to heuristic agent.")
    fallback = generate_fallback_quest(brand_name, has_stall, zone_name, booth_number, website_url, category, points_tier)
    fallback["note"] = f"Generated with built-in heuristic agent (Gemini API error: {last_error})."
    return fallback


def generate_fallback_diversion_quest(
    overcrowded_zone_name: str,
    target_brand_name: str,
    target_zone_name: str,
    target_booth_number: Optional[str] = None,
    bonus_points: int = 150
) -> Dict[str, Any]:
    """Generates a fallback crowd-redistribution surge quest when offline or API key is absent."""
    booth_str = f"at {target_booth_number}" if target_booth_number else "at their showcase stall"
    title = f"⚡ Flash Surge: Visit {target_brand_name} at {target_zone_name}!"
    description = (
        f"Beat the crowd rush at {overcrowded_zone_name}! "
        f"Head over to {target_zone_name} and check out the {target_brand_name} booth {booth_str}. "
        f"Experience an exclusive demo and scan the checkpoint in the next 15 minutes to earn +{bonus_points} BONUS Points!"
    )
    return {
        "title": title,
        "description": description,
        "quest_type": "stall_visit",
        "activity_type": "scavenger",
        "points_reward": bonus_points,
        "call_to_action": f"Head to {target_brand_name} in {target_zone_name}",
        "verification_method": "Scan Booth QR Checkpoint",
        "target_location": f"{target_zone_name} • {target_booth_number or 'Booth'}",
        "estimated_minutes": 10,
        "trivia_or_clue": f"Enjoy shorter lines and high bonus points while relaxing at {target_brand_name}!",
        "ai_generated": False,
        "model_used": "spatially-crowd-diversion-engine",
        "is_crowd_diversion": True,
        "diversion_from": overcrowded_zone_name,
        "diversion_to": target_zone_name,
    }


async def generate_crowd_diversion_quest(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    AI Agent that generates flash crowd-redistribution surge quests using Gemini 3.5 Flash Lite.
    Incentivizes attendees in an overcrowded venue spot to move toward low-density sponsor stalls.
    """
    overcrowded_zone = data.get("overcrowded_zone_name") or data.get("source_zone_name") or "Main Area"
    target_brand = data.get("brand_name") or data.get("target_brand_name") or "Featured Sponsor"
    target_zone = data.get("target_zone_name") or "Exhibition Hall"
    target_booth = data.get("target_booth_number") or data.get("booth_number") or ""
    bonus_points = int(data.get("bonus_points") or data.get("points_reward") or 150)
    event_name = data.get("event_name") or "the event"

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        fallback = generate_fallback_diversion_quest(
            overcrowded_zone, target_brand, target_zone, target_booth, bonus_points
        )
        fallback["note"] = "Generated with built-in heuristic agent (GEMINI_API_KEY not set)."
        return fallback

    prompt = f"""You are the Crowd Intelligence & Gamification AI Agent for Spatially, an intelligent spatial event operating system.
A venue area is currently experiencing high crowd congestion. Your mission is to generate a time-limited, highly appealing "SURGE DIVERSION QUEST" that motivates attendees to leave the congested area and visit a low-crowd sponsor stall.

SITUATION:
- Congested / Overcrowded Zone: '{overcrowded_zone}' (Attendees need to disperse from here)
- Target Sponsor Stall: '{target_brand}'
- Target Low-Crowd Zone: '{target_zone}' (Booth: {target_booth or 'Stall Area'})
- Reward Incentive: {bonus_points} BONUS Points (High incentive)
- Event: {event_name}

RULES:
1. The quest must entice attendees to leave '{overcrowded_zone}' and walk to '{target_zone}' to visit '{target_brand}'.
2. Frame it positively as an exclusive opportunity (e.g. "Beat the rush", "Flash Surge Bonus", "VIP Demo at {target_brand} with shorter lines").
3. Set a sense of urgency (e.g. "Next 15 minutes!").
4. Output STRICTLY raw JSON with NO markdown code fences.

JSON SCHEMA:
{{
  "title": "Punchy Flash Title (e.g. '⚡ Flash Surge: Visit {target_brand} in {target_zone} (+{bonus_points} Pts!)')",
  "description": "2-3 exciting sentences directing attendees away from {overcrowded_zone} towards {target_zone} to experience {target_brand} and scan QR",
  "quest_type": "stall_visit",
  "activity_type": "scavenger",
  "points_reward": {bonus_points},
  "call_to_action": "Head to {target_brand} Stall",
  "verification_method": "Scan Booth QR Checkpoint",
  "target_location": "{target_zone} • {target_booth or 'Booth'}",
  "estimated_minutes": 10,
  "trivia_or_clue": "Exciting fact or perk waiting at {target_brand}'s stall"
}}"""

    requested_model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite")
    models_to_try = [requested_model] + [m for m in MODELS_FALLBACK_LIST if m != requested_model]

    async with httpx.AsyncClient(timeout=15.0) as client:
        last_error = None
        for model in models_to_try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            payload = {
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {
                    "temperature": 0.7,
                    "maxOutputTokens": 600,
                    "responseMimeType": "application/json"
                }
            }

            try:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    data_json = response.json()
                    candidates = data_json.get("candidates", [])
                    if candidates:
                        text = candidates[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                        cleaned_text = text.strip()
                        if cleaned_text.startswith("```"):
                            lines = cleaned_text.split("\n")
                            cleaned_text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
                        parsed = json.loads(cleaned_text)
                        parsed["ai_generated"] = True
                        parsed["model_used"] = model
                        parsed["is_crowd_diversion"] = True
                        parsed["diversion_from"] = overcrowded_zone
                        parsed["diversion_to"] = target_zone
                        return parsed
                elif response.status_code in (404, 400):
                    last_error = f"Model {model} returned {response.status_code}"
                    continue
                else:
                    last_error = f"Gemini API returned status {response.status_code}: {response.text}"
                    break
            except Exception as e:
                last_error = str(e)
                continue

    fallback = generate_fallback_diversion_quest(
        overcrowded_zone, target_brand, target_zone, target_booth, bonus_points
    )
    fallback["note"] = f"Generated with built-in heuristic engine (Gemini API error: {last_error})."
    return fallback


