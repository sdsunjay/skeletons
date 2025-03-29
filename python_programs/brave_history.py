import os
import platform
import shutil
import sqlite3
from datetime import datetime, timedelta
from typing import List, Tuple, Optional, TypedDict

import click
import pytz

HISTORY_COPY_NAME = "History_copy"


class HistoryItem(TypedDict):
    url: str
    title: str
    visit_time: int


class SessionDict(TypedDict):
    start_day: str
    start: str
    end: str
    duration_hours: float


class DaySummary(TypedDict):
    day_start: str
    day_end: str
    sessions: List[SessionDict]
    total_duration_hours: float


def get_brave_history_path() -> str:
    system = platform.system()
    if system == "Windows":
        return os.path.join(
            os.environ["USERPROFILE"],
            "AppData",
            "Local",
            "BraveSoftware",
            "Brave-Browser",
            "User Data",
            "Default",
            "History",
        )
    elif system == "Darwin":  # macOS
        return os.path.expanduser(
            "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
        )
    elif system == "Linux":
        return os.path.expanduser(
            "~/.config/BraveSoftware/Brave-Browser/Default/History"
        )
    else:
        raise NotImplementedError(f"Unsupported OS: {system}")


def copy_file_to_current_directory_with_cache_check(
    source_path: str, dest_filename: str = HISTORY_COPY_NAME
) -> str:
    """
    Copies the Brave history SQLite file to the current directory if the destination file
    does not already exist or is older than 1 hour.
    """
    if not os.path.exists(source_path):
        raise FileNotFoundError(f"History file not found at {source_path}")

    dest_path = os.path.join(os.getcwd(), dest_filename)

    # Check if file exists and is recent (within 1 hour)
    if os.path.exists(dest_path):
        modified_time = datetime.fromtimestamp(os.path.getmtime(dest_path))
        if datetime.now() - modified_time < timedelta(hours=1):
            print(f"Recent history file already exists at {dest_path}, skipping copy.")
            return dest_path

    try:
        shutil.copy2(source_path, dest_path)
        print(f"File copied successfully to {dest_path}")
        return dest_path
    except (IOError, shutil.SameFileError) as e:
        raise RuntimeError(f"Error copying file: {e}")


def copy_file_to_current_directory(
    source_path: str, dest_filename: str = HISTORY_COPY_NAME
) -> str:
    """Copies the Brave history SQLite file to the current directory."""
    if not os.path.exists(source_path):
        raise FileNotFoundError(f"History file not found at {source_path}")

    dest_path = os.path.join(os.getcwd(), dest_filename)

    try:
        shutil.copy2(source_path, dest_path)
        print(f"File copied successfully to {dest_path}")
        return dest_path
    except (IOError, shutil.SameFileError) as e:
        raise RuntimeError(f"Error copying file: {e}")


def get_full_brave_visit_history(history_path: str) -> List[Tuple[str, str, int]]:
    """
    Extracts full Brave browser visit history by joining visits and urls tables.

    Returns:
        List of tuples: (url, title, visit_time)
    """
    try:
        with sqlite3.connect(history_path) as conn:
            cursor = conn.cursor()
            query = """
                SELECT
                    urls.url,
                    urls.title,
                    visits.visit_time
                FROM
                    visits
                JOIN
                    urls
                ON
                    visits.url = urls.id
                ORDER BY visits.visit_time DESC
            """
            cursor.execute(query)
            return cursor.fetchall()
    except sqlite3.DatabaseError as e:
        raise RuntimeError(f"Database error: {e}")


def convert_chromium_timestamp(chromium_timestamp: int) -> datetime:
    """
    Converts a Chromium timestamp (microseconds since Jan 1, 1601) to a Python datetime object.
    """
    epoch_start = datetime(1601, 1, 1)
    return epoch_start + timedelta(microseconds=chromium_timestamp)


def format_readable_time_utc(timestamp: datetime) -> str:
    """Formats datetime to a readable string."""
    return timestamp.strftime("%Y-%m-%d %H:%M")


def format_readable_time(dt: datetime, timezone: str = "America/New_York") -> str:
    """
    Formats a datetime string into a readable string format.
    """
    tz = pytz.timezone(timezone)
    local_dt = dt.replace(tzinfo=pytz.utc).astimezone(tz)
    return local_dt.strftime("%Y-%m-%d %I:%M %p")


def format_readable_day_and_time(
    dt: datetime, timezone: str = "America/New_York"
) -> str:
    tz = pytz.timezone(timezone)
    local_dt = dt.replace(tzinfo=pytz.utc).astimezone(tz)
    return local_dt.strftime("%a %Y-%m-%d %I:%M %p")


def get_history_urls(
    history: List[Tuple[str, str, int]],
    limit: Optional[int] = None,
    filter_date: Optional[datetime] = None,
) -> List[HistoryItem]:
    """
    Filters and returns browsing history records in a structured format.

    Args:
        history: A list of tuples (url, title, visit_time) from the database.
        limit: Maximum number of records to return.
        filter_date: Optional date to filter history items by (timezone-aware).

    Returns:
        A list of HistoryItem dictionaries.
    """
    all_items: List[HistoryItem] = []

    for i, (url, title, last_visit_time) in enumerate(history):
        if limit and i >= limit:
            break

        dt = convert_chromium_timestamp(last_visit_time)

        if filter_date:
            # Convert Chromium timestamp to same timezone as filter_date
            localized_dt = pytz.utc.localize(dt).astimezone(filter_date.tzinfo)
            if localized_dt.date() != filter_date.date():
                continue

        all_items.append({"url": url, "title": title, "visit_time": last_visit_time})

    return all_items


def create_session(
    session_start: datetime, session_end: datetime
) -> Optional[SessionDict]:
    """
    Creates a session dictionary if the session duration is longer than 60 seconds.

    Args:
        session_start (datetime): Start time of the session.
        session_end (datetime): End time of the session.

    Returns:
        SessionDict or empty dict if too short.
    """
    duration_seconds = (session_end - session_start).total_seconds()

    if duration_seconds <= 60:
        return None  # Return empty dict for sessions <= 60 seconds

    session: SessionDict = {
        "start_day": format_readable_day_and_time(session_start),
        "start": format_readable_time(session_start),
        "end": format_readable_time(session_end),
        "duration_hours": float(duration_seconds / 3600),
    }
    return session


def filter_and_sort_timestamps(
    full_history: List[Tuple[str, str, int]], cutoff: datetime
) -> List[datetime]:
    """
    Filters and sorts visit timestamps based on a cutoff datetime.
    """
    return sorted(
        convert_chromium_timestamp(visit_time)
        for _, _, visit_time in full_history
        if convert_chromium_timestamp(visit_time) >= cutoff
    )


def finalize_day(
    sessions: List[SessionDict], include_sessions: bool = False
) -> DaySummary:
    """
    Creates a daily summary from a list of sessions.

    Adds the day of the week based on the first session's start time.

    Args:
        sessions (List[Dict[str, str]]): List of session dictionaries for the day.
        include_sessions (bool): Whether to include all the sessions for the day or not.

    Returns:
        Optional[Dict[str, object]]: Summary with start time, day of week, and total duration.
    """

    day_start_str: str = sessions[0]["start_day"]
    day_end_str: str = sessions[-1]["end"]

    day_summary: DaySummary = {
        "day_start": day_start_str,
        "day_end": day_end_str,
        "sessions": sessions if include_sessions else [],
        "total_duration_hours": sum(float(s["duration_hours"]) for s in sessions),
    }
    return day_summary


def get_precise_sessions_by_day(
    full_history: List[Tuple[str, str, int]],
    days: int = 30,
    gap_minutes: int = 60,
    include_sessions: bool = False,
) -> List[DaySummary]:
    """
    Groups browsing history into day-level summaries based on visit gaps.

    Args:
        full_history (List[Tuple[str, str, int]]): Complete visit history (url, title, visit_time).
        days (int): Number of days to look back from current time.
        gap_minutes (int): Time gap (in minutes) to separate sessions.
        include_sessions (bool): Whether to include all the sessions for the day or not.

    Returns:
        List[Dict[str, object]]: List of day summaries with start and total usage duration.
    """
    now = datetime.now()
    cutoff = now - timedelta(days=days)
    gap_threshold = timedelta(minutes=gap_minutes)
    gap_day = timedelta(minutes=(gap_minutes * 4))

    timestamps = filter_and_sort_timestamps(full_history, cutoff)
    if not timestamps:
        return []

    days_list = []
    current_day_sessions = []
    session_start = timestamps[0]
    session_end = timestamps[0]

    for current_time in timestamps[1:]:
        gap = current_time - session_end

        if gap > gap_day:
            session = create_session(session_start, session_end)
            if session:
                current_day_sessions.append(session)
                day_summary = finalize_day(
                    current_day_sessions, include_sessions=include_sessions
                )
                days_list.append(day_summary)
                current_day_sessions = []
            session_start = current_time

        elif gap > gap_threshold:
            session = create_session(session_start, session_end)
            if session:
                current_day_sessions.append(session)
            session_start = current_time

        session_end = current_time

    # Final session/day
    session = create_session(session_start, session_end)
    if session:
        current_day_sessions.append(session)
        day_summary = finalize_day(current_day_sessions, include_sessions)
        days_list.append(day_summary)

    return days_list


def get_precise_sessions(
    full_history: List[Tuple[str, str, int]], days: int = 30, gap_minutes: int = 60
) -> List[SessionDict]:
    """Groups browsing activity into sessions with >=gap_minutes break defining new session."""

    now = datetime.now()
    cutoff = now - timedelta(days=days)
    gap_threshold = timedelta(minutes=gap_minutes)

    timestamps = sorted(
        convert_chromium_timestamp(visit_time)
        for _, _, visit_time in full_history
        if convert_chromium_timestamp(visit_time) >= cutoff
    )

    if not timestamps:
        return []

    sessions = []
    session_start = timestamps[0]
    session_end = timestamps[0]

    for current_time in timestamps[1:]:
        gap = current_time - session_end

        if gap > gap_threshold:
            session_data = create_session(session_start, session_end)
            if session_data:
                sessions.append(session_data)
            session_start = current_time

        session_end = current_time

    # Final session
    session_data = create_session(session_start, session_end)
    if session_data:
        sessions.append(session_data)

    return sessions


@click.group()
@click.pass_context
def cli(ctx):
    """CLI for Brave history analysis."""
    history_path = get_brave_history_path()
    copied_path = copy_file_to_current_directory_with_cache_check(history_path)
    ctx.ensure_object(dict)
    ctx.obj["history"] = get_full_brave_visit_history(copied_path)


@cli.command()
@click.argument("date", type=str)
@click.option("--days", default=30, help="Number of days back to analyze.", type=int)
@click.option(
    "--gap-minutes",
    default=60,
    help="Minutes of inactivity to define a new session.",
    type=int,
)
@click.option("--include-urls", default=False, help=".", type=bool)
@click.pass_context
def show_sessions(ctx, date: str, days: int, gap_minutes: int, include_urls: bool):
    """Show sessions for a specific date (format: YYYY-MM-DD)."""

    try:
        # Step 1: Parse date string into naive datetime
        naive_dt = datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        raise click.BadParameter("Date must be in YYYY-MM-DD format.")

    all_days = get_precise_sessions_by_day(
        ctx.obj["history"], days=days, gap_minutes=gap_minutes, include_sessions=True
    )

    if include_urls:
        history_urls: List[HistoryItem] = get_history_urls(
            ctx.obj["history"], filter_date=naive_dt
        )

        for item in history_urls:
            readable_time = format_readable_time(
                convert_chromium_timestamp(item["visit_time"])
            )
            click.echo(
                f"{item['url'][:40]:40}  {item['title'][:40]:40}  {readable_time}"
            )

    target_date = naive_dt.date()

    # Find sessions for the date
    all_matching_sessions = []
    for day in all_days:
        sessions = day.get("sessions", [])
        for session in sessions:
            try:
                session_start = datetime.strptime(session["start"], "%Y-%m-%d %I:%M %p")
                if session_start.date() == target_date:
                    all_matching_sessions.append(session)
            except Exception as e:
                click.echo(f"Skipping invalid session entry: {e}", err=True)

    # Output matching sessions
    if not all_matching_sessions:
        click.echo("No sessions found for that date.")
    if not all_days:
        click.echo(f"No days found for {date}.")
        return

    click.echo(f"Sessions for {date}:")

    for session in all_matching_sessions:
        click.echo(
            f"  Start: {session['start']}, End: {session['end']}, Duration: {session['duration_hours']} hours"
        )

    # click.echo(f"Total duration: {sessions_for_date['total_duration_hours']} hours")


@cli.command()
@click.option("--days", default=60, help="Number of days back to analyze.", type=int)
@click.option(
    "--gap-minutes",
    default=60,
    help="Minutes of inactivity to define a new session.",
    type=int,
)
@click.pass_context
def show_summary(ctx, days: int, gap_minutes: int):
    """Display total session durations summarized by day."""

    all_days = get_precise_sessions_by_day(
        ctx.obj["history"], days=days, gap_minutes=gap_minutes
    )
    for day in all_days:
        click.echo(
            f"{day.get('day_start')} - {day.get('day_end')}: {day.get('total_duration_hours')}"
        )


if __name__ == "__main__":
    cli()
