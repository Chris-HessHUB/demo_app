from flask import Flask, jsonify
import os
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)

def get_db_connection():
    """
    Establishes a connection to the MySQL database using environment variables.
    Expected environment variables:
      - MYSQL_HOST
      - MYSQL_DB
      - MYSQL_USER
      - MYSQL_PASSWORD
    """
    host = os.environ.get("MYSQL_HOST", "localhost")
    database = os.environ.get("MYSQL_DB", "flaskdb")
    user = os.environ.get("MYSQL_USER", "flaskuser")
    password = os.environ.get("MYSQL_PASSWORD", "flaskpass")
    
    try:
        connection = mysql.connector.connect(
            host=host,
            database=database,
            user=user,
            password=password
        )
        if connection.is_connected():
            return connection
    except Error as e:
        app.logger.error(f"Error connecting to MySQL: {e}")
    return None

u/app.route("/")
def index():
    return f"Welcome to the Flask App running in {os.environ.get('APP_ENV', 'development')} mode!"

u/app.route("/dbtest")
def db_test():
    """
    A simple endpoint to test the MySQL connection.
    Executes a query to get the current time from the database.
    """
    connection = get_db_connection()
    if connection is None:
        return jsonify({"error": "Failed to connect to MySQL database"}), 500
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT NOW();")
        current_time = cursor.fetchone()
        return jsonify({
            "message": "Successfully connected to MySQL!",
            "current_time": current_time[0]
        })
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection and connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == "__main__":
    debug_mode = os.environ.get("DEBUG", "false").lower() == "true"
    app.run(host="0.0.0.0", port=5000, debug=debug_mode)