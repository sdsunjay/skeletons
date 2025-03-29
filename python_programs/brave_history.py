import os
import platform
import shutil
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

import pytz

HISTORY_COPY_NAME = 'History_copy'

def get_brave_history_path() -> str:
    system = platform.system()
    if system == 'Windows':
        return os.path.join(
            os.environ['USERPROFILE'],
            "AppData", "Local", "BraveSoftware", "Brave-Browser", "User Data", "Default", "History"
        )
    elif system == 'Darwin':  # macOS
        return os.path.expanduser(
            "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
        )
    elif system == 'Linux':
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


def copy_file_to_current_directory(source_path: str, dest_filename: str = HISTORY_COPY_NAME) -> str:
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
    """Converts Chromium timestamp to Python datetime."""
    epoch_start = datetime(1601, 1, 1)
    return epoch_start + timedelta(microseconds=chromium_timestamp)


def format_readable_time_utc(timestamp: datetime) -> str:
    """Formats datetime to a readable string."""
    return timestamp.strftime('%Y-%m-%d %H:%M')

def format_readable_time(dt: datetime, timezone: str = 'America/New_York') -> str:
    tz = pytz.timezone(timezone)
    local_dt = dt.replace(tzinfo=pytz.utc).astimezone(tz)
    return local_dt.strftime('%Y-%m-%d %I:%M %p')


def display_history(history: List[Tuple[str, str, int, int]], limit: Optional[int] = None) -> None:
    """Prints browsing history in a readable format."""
    for i, (url, title, visit_count, last_visit_time) in enumerate(history):
        if limit and i >= limit:
            break
        readable_time = format_readable_time(convert_chromium_timestamp(last_visit_time))
        print(f"[{i+1}] URL: {url}\n     Title: {title}\n     Visits: {visit_count}\n     Last Visit: {readable_time}\n")

def create_session(session_start: datetime, session_end: datetime) -> Dict[str, str]:
    duration_seconds = (session_end - session_start).total_seconds()

    if duration_seconds <= 60:
        return {}  # Return empty dict for sessions <= 60 seconds

    return {
        'start': format_readable_time(session_start),
        'end': format_readable_time(session_end),
        'duration_hours': f"{duration_seconds / 3600:.2f}"
    }


def get_precise_sessions(
    full_history: List[Tuple[str, str, int]],
    days: int = 30,
    gap_minutes: int = 60
) -> List[Dict[str, str]]:
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


def main() -> None:
    try:
        history_path = get_brave_history_path()
        copied_path = copy_file_to_current_directory_with_cache_check(history_path)
        full_history = get_full_brave_visit_history(copied_path)
        sessions = get_precise_sessions(full_history, days=60, gap_minutes=60)
        # display_history(history, limit=20)  # Limit to 20 most recent entries
        for day in sessions:
            print(day)
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()

