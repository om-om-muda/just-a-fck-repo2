FROM python:3.9

WORKDIR /app

# Copy pre-downloaded wheels
COPY ./custom-wheels /wheels

# Copy the requirements file
COPY requirements.txt .

# Install dependencies from wheels
RUN pip install --no-index --find-links=/wheels -r requirements.txt

# Copy the rest of the application
COPY . .

# Create the run script with project name detection
RUN echo '#!/bin/bash\n\
PROJECT_NAME=$(find . -maxdepth 2 -type f -name "wsgi.py" | cut -d "/" -f 2)\n\
if [ -z "$PROJECT_NAME" ]; then\n\
    echo "Error: Could not find Django project."\n\
    exit 1\n\
fi\n\
echo "Django project name: ${PROJECT_NAME}"\n\
python manage.py migrate\n\
python manage.py collectstatic --noinput\n\
gunicorn ${PROJECT_NAME}.wsgi:application' > /app/run.sh && \
    chmod +x /app/run.sh

# Run the application
CMD ["/app/run.sh"]