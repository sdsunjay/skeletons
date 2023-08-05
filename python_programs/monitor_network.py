import psutil
import time
import socket

def get_process_connections(pid):
    """
    Get detailed information about network connections for a given process.

    Parameters:
    - pid (int): The process identifier.

    Returns:
    - list: A list of dictionaries containing connection and process details
    """
    connections_info = []
    try:
        process = psutil.Process(pid)
        connections = process.connections()
        process_start_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(process.create_time()))
        process_user = process.username()
        for idx, conn in enumerate(connections):
            connection_info = {
                'local_address': f"{conn.laddr.ip}:{conn.laddr.port}" if conn.laddr else "N/A",
                'remote_address': f"{conn.raddr.ip}:{conn.raddr.port}" if conn.raddr else "N/A",
                'status': conn.status,
                'type': conn.type,
                'family': socket.AddressFamily(conn.family).name if conn.family else "N/A",
                'pid': pid,
                'start_time': process_start_time,
                'user': process_user
            }
            connections_info.append(connection_info)
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        pass
    return connections_info

def block_connection(connection):
    """
    Temporarily block a suspicious connection.

    Parameters:
    - connection (dict): A dictionary containing details about the connection to block.

    Note:
    This function simulates the action of blocking a connection
    In a real-world scenario, additional
    steps would be required to actually terminate or block the connection.
    """
    try:
        conn = psutil._psplatform.net_connections()[connection['family']][connection['type']][connection['local_address']]
        conn.pid = connection['pid']
        conn.status = 'CLOSE_WAIT'  # Simulate closing the connection temporarily
    except (AttributeError, KeyError, psutil.NoSuchProcess, psutil.AccessDenied):
        pass


def monitor_network_activity(interval, top_n=20):
    """
    Monitor network activity continuously and display top applications by network activity.

    Parameters:
    - interval (int): The interval (in seconds) at which to monitor network activity.
    - top_n (int, optional): The number of top applications to display. Defaults to 20.

    Note:
    This function runs indefinitely until interrupted (e.g., by pressing Ctrl+C).
    """
    while True:
        try:
            # Get a list of all running processes
            processes = psutil.process_iter(['pid', 'name'])

            # Create a dictionary to store the network activity of each process
            network_activity = {}

            for process in processes:
                pid = process.info['pid']
                name = process.info['name']

                # Get detailed information about the network connections for the process
                connections_info = get_process_connections(pid)

                # If there are established connections, store the process name and connection details
                if connections_info:
                    network_activity[name] = connections_info

            # Sort applications based on the number of connections (highest to lowest)
            sorted_network_activity = dict(sorted(network_activity.items(), key=lambda item: len(item[1]), reverse=True))

            # Display the top N applications with the highest number of connections
            print("Top Applications by Network Activity:")
            for idx, (app_name, connection_details) in enumerate(sorted_network_activity.items()):
                print(f"{idx+1}. {app_name}: {len(connection_details)} established connection(s)")
                if idx == top_n - 1:
                    break


                # Display detailed information about each connection for the top N applications
                for pid_connection_count, conn in enumerate(connection_details):
                    if pid_connection_count >= 2:  # Limit to a maximum of 2 connection details
                        break
                    print(f"  - Local Address: {conn['local_address']}")
                    print(f"    Remote Address: {conn['remote_address']}")
                    print(f"    Status: {conn['status']}")
                    print(f"    PID: {conn['pid']}")
                    print(f"    Type: {conn['type']}")
                    print(f"    Family: {conn['family']}")
                    print(f"    Start Time: {conn['start_time']}")
                    print(f"    User: {conn['user']}")
                    # Simulate blocking suspicious connections temporarily (ethical consideration)
                    #if conn['status'] == 'ESTABLISHED' and conn['family'] == socket.AF_INET:
                    #    block_connection(conn)

        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
            break

        # Pause for the specified interval before monitoring again
        print(f"sleeping for {interval}")
        time.sleep(interval)

if __name__ == "__main__":
    print("Monitoring your network activity...")
    print("Press Ctrl + C to stop monitoring.")

    # Explain to the reader that you need proper authorization
    print("As responsible cyber experts, Alex and Alladin understand the importance of privacy.")
    print("To perform network monitoring, they need proper authorization.")
    print("Unauthorized access to sensitive information is against ethical principles.")

    try:
        # Call the monitor_network_activity function with a monitoring interval of 5 seconds
        monitor_network_activity(interval=10, top_n=20)
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")

