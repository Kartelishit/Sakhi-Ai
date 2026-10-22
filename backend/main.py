import os
import re
import httpx

from typing import Literal
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


# ==================================================
# SHEGUARD BACKEND
# ==================================================

app = FastAPI(title="SHEGUARD AI Backend")


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Local demo only
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ==================================================
# AI PROVIDERS (tried in order, with automatic fallback)
# ==================================================
#
# Environment variables:
#   GROQ_API_KEY         one key, or several separated by commas
#   OPENROUTER_API_KEY   one key, or several separated by commas
#   OPENROUTER_MODEL     optional, defaults to openai/gpt-oss-20b:free

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "openai/gpt-oss-20b"

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_MODEL = os.getenv(
    "OPENROUTER_MODEL", "openrouter/free"
)

# Only the most recent turns are sent (fewer tokens = fewer rate limits).
MAX_HISTORY_MESSAGES = 10

URGENT_TAG = "[URGENT]"

DEMO_NOTICE = (
    "This is AI-generated support and may be incorrect. It is not a "
    "replacement for a counsellor, doctor or lawyer. For serious "
    "concerns, please talk to a trusted person. If you are in "
    "immediate danger, call 112."
)


def _keys(env_name: str) -> list[str]:
    raw = os.getenv(env_name, "")
    return [k.strip() for k in raw.split(",") if k.strip()]


def build_providers() -> list[dict]:
    """Build the provider/key list fresh on each request so that
    changing environment variables only needs a restart."""
    providers: list[dict] = []

    for number, key in enumerate(_keys("GROQ_API_KEY"), start=1):
        providers.append(
            {
                "name": "Groq",
                "label": f"Groq (key {number})",
                "url": GROQ_URL,
                "model": GROQ_MODEL,
                "key": key,
                "extra": {"reasoning_effort": "low"},
                "headers": {},
            }
        )

    for number, key in enumerate(_keys("OPENROUTER_API_KEY"), start=1):
        providers.append(
            {
                "name": "OpenRouter",
                "label": f"OpenRouter (key {number})",
                "url": OPENROUTER_URL,
                "model": OPENROUTER_MODEL,
                "key": key,
                "extra": {"reasoning": {"effort": "low"}},
                "headers": {
                    "HTTP-Referer": "http://localhost",
                    "X-Title": "SHEGUARD",
                },
            }
        )

    return providers


# ==================================================
# REQUEST AND RESPONSE MODELS
# ==================================================

Category = Literal[
    "Feeling low or stressed",
    "Bullying or ragging",
    "Online harassment",
    "Unwanted behaviour or stalking",
    "Discrimination",
    "Family or relationship problem",
    "Something else",
]


class AssessRequest(BaseModel):
    category: Category
    message: str = Field(min_length=1, max_length=1200)
    immediate_danger: bool = False


class AssessResponse(BaseModel):
    category: str
    urgency: str
    summary: str
    next_steps: list[str]
    human_help: bool = True
    demo_notice: str


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=3000)


class ChatRequest(BaseModel):
    category: Category
    immediate_danger: bool = False
    # Full conversation so far, oldest first. Kept in the app's memory
    # only; the backend stores nothing between requests.
    messages: list[ChatTurn] = Field(min_length=1, max_length=60)


class ChatResponse(BaseModel):
    category: str
    urgency: str
    reply: str
    human_help: bool = True
    demo_notice: str


class SummaryRequest(BaseModel):
    category: Category
    audience: Literal["parent", "teacher"] = "parent"
    immediate_danger: bool = False
    messages: list[ChatTurn] = Field(min_length=1, max_length=60)


class SummaryResponse(BaseModel):
    audience: str
    summary: str


# ==================================================
# PROMPT PIECES
# ==================================================

# Change this block if you target a country other than India.
HELPLINES = """
HELPLINES YOU MAY MENTION (use only these, never invent numbers):
- Emergency (police, ambulance): 112
- Women Helpline: 181
- Cyber crime helpline: 1930, and the portal cybercrime.gov.in
- Tele-MANAS (mental health support, 24/7): 14416
- Childline (if the student is under 18): 1098
"""

PERSONA = """
You are SHEGUARD, a caring, non-judgemental support companion
for girls and young women in college. Students come to you when
they feel hurt, scared, stressed, harassed or alone.

This application is a college project demonstration.

TONE:
- Warm, calm, like a kind older sister or a good friend.
- Simple, everyday English. Never preachy, never robotic.
- Start by acknowledging how she feels. Comfort comes first.
- Believe her. Never blame, shame, or question her choices.
- Never diagnose. Never promise secrecy or that things will be fine.
- Never ask for names, phone numbers, or addresses.
- Never encourage revenge or risky confrontation.
- Do not invent details she did not share.
- Do not pretend to contact anyone on her behalf.

SAFETY:
- If she may be in immediate danger, put safety first: get to a
  safe place, contact a trusted person, call 112.
- If she mentions hurting herself or not wanting to live, respond
  with deep care, encourage her to reach a trusted person right
  now, and mention Tele-MANAS 14416 and 112.
- Treat the immediate_danger field as a serious signal.

LEGAL INFORMATION:
- Give general information only, and say it is not legal advice.
- Keep it practical: options like writing down what happened,
  saving screenshots, complaining to the college Internal
  Complaints Committee or Anti-Ragging Committee, filing a
  complaint or FIR at a police station, or reporting online
  harassment at cybercrime.gov.in.
- Do not quote specific law sections or punishments unless
  you are completely sure.
"""

OUTPUT_RULES = """
REPLY FORMAT (plain text, no JSON, no markdown symbols like ** or #):

Write the reply in these labelled sections, each label on its own
line followed by a colon. Use only the sections that are relevant
to her situation. Always include the first one.

How you might be feeling:
2 to 3 warm sentences that acknowledge and comfort her.

Emotional support:
Short, kind guidance on coping right now (breathing, talking to
someone, being gentle with herself, not facing it alone).

What you can do now:
2 to 4 short practical steps, each on its own line starting
with "- ".

Safety:
Only if there is any risk. Concrete steps to stay safe.

Know your rights:
Only if harassment, stalking, bullying, discrimination or a
crime is involved. General legal information and where to report.

Who can help:
Trusted people (parent, friend, teacher, counsellor) and relevant
helplines from the list.

If she is just feeling low or stressed, skip Safety and
Know your rights. Keep the whole reply under about 250 words.
End with one gentle question or an offer to keep talking.

If the situation involves immediate danger or needs urgent human
intervention, begin your reply with the exact tag [URGENT] and a
space. Otherwise do not include any tag.
""" + HELPLINES

CHAT_RULES = """
ONGOING CONVERSATION:
- This is a continuing chat. Remember what she already shared.
- On your first reply, use the full labelled format.
- On later replies, do NOT repeat the full format or earlier
  advice. Answer her latest message in a natural, warm way, and
  use a labelled section only if it genuinely helps (for example,
  "What you can do now:" when she asks what to do next).
- Do not re-introduce yourself after the first reply.
- If her new message shows danger, switch to an urgent, caring tone.
"""


SUMMARY_RULES = """
You help a student write ONE short message that she will send to
her {audience} to ask for help. Write it as the student, in the
first person ("I").

You are given a conversation between the student and SHEGUARD, an
AI support companion. Base the message ONLY on what the student
herself said. Use SHEGUARD's replies only to understand the
context. Never include SHEGUARD's advice, and never mention the
app or AI.

RULES:
- 3 to 5 short sentences, at most 80 words.
- Plain text only: no markdown, bullet points, headings, emojis,
  or subject line.
- Be accurate. Never add, guess or exaggerate. If something was not
  said (who, when, how often), leave it out.
- Do not include names, phone numbers or addresses unless the
  student wrote them herself.
- Cover: what happened, how it is affecting her, and what she is
  asking for (for example to talk, or for support and guidance).
- Tone: calm, respectful and honest. Start with "{greeting}".
- End with one clear, polite request. {ending}
- If she may be in immediate danger, or she mentions hurting
  herself, say clearly that she needs help urgently and ask them to
  contact her right away.
- Write in the same language the student used.
- Output only the message text, nothing else.
"""

SUMMARY_AUDIENCE = {
    "parent": {
        "audience": "parent or guardian",
        "greeting": "Hi,",
        "ending": "Ask to talk when they have time.",
    },
    "teacher": {
        "audience": "teacher or counsellor",
        "greeting": "Hello,",
        "ending": (
            "Ask for a time to speak and for guidance on what to do next."
        ),
    },
}


# ==================================================
# AI HELPERS (multi-provider with fallback)
# ==================================================

def clean_reply(text: str) -> tuple[str, bool]:
    """Turn raw model text into a clean reply.
    Returns (reply, is_urgent)."""

    # Remove reasoning blocks some models leak into the content.
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = text.strip()

    # Remove code fences if the model wrapped the answer in them.
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\s*", "", text)
        text = re.sub(r"\s*```$", "", text).strip()

    # Detect and strip the urgent tag.
    urgent = False
    if text.upper().startswith(URGENT_TAG):
        urgent = True
        text = text[len(URGENT_TAG):].strip()

    # Strip stray markdown, but keep our "- " bullets and "Label:" lines.
    text = re.sub(r"(\*\*|__)", "", text)
    text = re.sub(r"^\s{0,3}#{1,6}\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"^\s*[*•]\s+", "- ", text, flags=re.MULTILINE)

    return text.strip(), urgent


async def call_provider(client: httpx.AsyncClient, provider: dict,
                        messages: list[dict], temperature: float = 0.6) -> str:
    payload = {
        "model": provider["model"],
        "messages": messages,
        "temperature": temperature,
        # Reasoning models spend tokens on thinking, so leave room
        # or the reply gets cut off or comes back empty.
        "max_tokens": 2000,
        **provider["extra"],
    }

    response = await client.post(
        provider["url"],
        headers={
            "Authorization": f"Bearer {provider['key']}",
            "Content-Type": "application/json",
            **provider["headers"],
        },
        json=payload,
    )
    response.raise_for_status()

    data = response.json()

    # OpenRouter can return HTTP 200 with an error object inside.
    if isinstance(data, dict) and data.get("error"):
        raise ValueError(f"Provider error: {str(data['error'])[:200]}")

    content = data["choices"][0]["message"].get("content")

    if not isinstance(content, str) or not content.strip():
        raise ValueError("Empty response (model may have run out of tokens).")

    return content


async def call_ai(messages: list[dict],
                  temperature: float = 0.6) -> tuple[str, bool]:
    """Try every configured provider/key in order until one works.
    Returns (reply_text, is_urgent)."""

    providers = build_providers()

    if not providers:
        raise HTTPException(
            status_code=503,
            detail=(
                "No AI API key is configured. Set GROQ_API_KEY and/or "
                "OPENROUTER_API_KEY on the backend."
            ),
        )

    rate_limited = False
    errors: list[str] = []

    async with httpx.AsyncClient(timeout=45.0) as client:
        for provider in providers:
            label = provider["label"]

            try:
                content = await call_provider(client, provider, messages, temperature)
                reply, urgent = clean_reply(content)

                if not reply:
                    raise ValueError("Reply was empty after cleaning.")

                print(f"AI reply served by {label}")
                return reply, urgent

            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                body = exc.response.text[:300]
                print(f"{label} failed with HTTP {status}: {body}")
                errors.append(f"{label}: HTTP {status}")

                if status in (402, 413, 429):
                    rate_limited = True
                # Any failure (bad key, rate limit, 5xx): try the next one.
                continue

            except httpx.RequestError as exc:
                print(f"{label} connection error: {type(exc).__name__}")
                errors.append(f"{label}: connection error {type(exc).__name__}")
                continue

            except (KeyError, IndexError, ValueError, TypeError, AttributeError) as exc:
                print(f"{label} invalid response: {type(exc).__name__}: {exc}")
                errors.append(f"{label}: invalid response {type(exc).__name__}")
                continue

    if rate_limited:
        raise HTTPException(
            status_code=429,
            detail=(
                "The AI service is busy right now. "
                "Please wait a minute and try again."
            ),
        )

    raise HTTPException(
        status_code=502,
        detail="No AI provider could process the request. " + " | ".join(errors),
    )


# ==================================================
# HEALTH CHECK
# ==================================================

@app.get("/health")
def health():
    providers = build_providers()
    return {
        "status": "ok",
        "ai_configured": bool(providers),
        "providers": [f"{p['label']} ({p['model']})" for p in providers],
    }


# ==================================================
# ONE-SHOT ASSESSMENT (kept for compatibility)
# ==================================================

@app.post("/assess", response_model=AssessResponse)
async def assess(data: AssessRequest):

    user_prompt = (
        f"Concern category: {data.category}\n"
        f"Immediate danger reported: "
        f"{'Yes' if data.immediate_danger else 'No'}\n\n"
        f"Student's message:\n{data.message}"
    )

    reply, urgent = await call_ai(
        [
            {"role": "system", "content": PERSONA + OUTPUT_RULES},
            {"role": "user", "content": user_prompt},
        ]
    )

    # Safety: the student's own danger flag always wins.
    urgency = "urgent" if (urgent or data.immediate_danger) else "support recommended"

    return AssessResponse(
        category=data.category,
        urgency=urgency,
        summary=reply[:3000],
        next_steps=[],
        human_help=True,
        demo_notice=DEMO_NOTICE,
    )


# ==================================================
# CONTINUOUS CONVERSATION
# The app sends the whole conversation each time.
# Nothing is stored on the server.
# ==================================================

@app.post("/chat", response_model=ChatResponse)
async def chat(data: ChatRequest):

    # Keep only the most recent turns, and make sure the
    # conversation starts with a student message.
    turns = data.messages[-MAX_HISTORY_MESSAGES:]
    while turns and turns[0].role != "user":
        turns = turns[1:]

    if not turns or turns[-1].role != "user":
        raise HTTPException(
            status_code=422,
            detail="The last message in the conversation must be from the student.",
        )

    context = (
        f"Concern category: {data.category}\n"
        f"Immediate danger reported by the student: "
        f"{'Yes' if data.immediate_danger else 'No'}\n"
        f"Number of messages so far: {len(data.messages)}"
    )

    messages: list[dict] = [
        {
            "role": "system",
            "content": PERSONA + CHAT_RULES + OUTPUT_RULES + "\n" + context,
        }
    ]
    for turn in turns:
        messages.append({"role": turn.role, "content": turn.content})

    reply, urgent = await call_ai(messages)

    # Safety: the student's own danger flag always wins.
    urgency = "urgent" if (urgent or data.immediate_danger) else "support recommended"

    return ChatResponse(
        category=data.category,
        urgency=urgency,
        reply=reply[:3000],
        human_help=True,
        demo_notice=DEMO_NOTICE,
    )


# ==================================================
# SHAREABLE SUMMARY
# Turns the conversation into one short message the student
# can send to a parent or teacher. Nothing is stored.
# ==================================================

@app.post("/summary", response_model=SummaryResponse)
async def summary(data: SummaryRequest):

    turns = data.messages[-40:]
    while turns and turns[0].role != "user":
        turns = turns[1:]

    if not any(t.role == "user" for t in turns):
        raise HTTPException(
            status_code=422,
            detail="There is nothing to summarise yet.",
        )

    lines: list[str] = []
    for t in turns:
        if t.role == "user":
            lines.append(f"Student: {t.content.strip()}")
        else:
            # Advice is only context, so keep it short.
            lines.append(f"SHEGUARD: {t.content.strip()[:500]}")
    transcript = "\n".join(lines)

    cfg = SUMMARY_AUDIENCE[data.audience]
    system_prompt = SUMMARY_RULES.format(**cfg)

    user_prompt = (
        f"Concern category: {data.category}\n"
        f"Student marked immediate danger: "
        f"{'Yes' if data.immediate_danger else 'No'}\n\n"
        f"Conversation:\n{transcript}\n\n"
        f"Write the message now."
    )

    text, _ = await call_ai(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=0.3,  # lower = more faithful, fewer invented details
    )

    # Tidy: drop wrapping quotes and a stray "Message:" label.
    text = text.strip().strip('"\u201c\u201d').strip()
    text = re.sub(r"^(message|summary)\s*:\s*", "", text, flags=re.IGNORECASE)
    text = text.strip().strip('"\u201c\u201d').strip()

    if not text:
        raise HTTPException(
            status_code=502,
            detail="The summary came back empty. Please try again.",
        )

    return SummaryResponse(audience=data.audience, summary=text[:900])
