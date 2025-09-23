FROM python:3.9-slim

# Install ping (iputils-ping) for troubleshooting
RUN apt-get update && apt-get install -y iputils-ping && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 5000
ENV FLASK_APP=app.py

CMD ["python", "app.py"]