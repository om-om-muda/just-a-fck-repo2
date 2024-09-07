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

# Create the run script
RUN echo '#!/bin/bash\n\
python manage.py migrate\n\
python manage.py collectstatic --noinput\n\
gunicorn elf.wsgi:application' > /app/run.sh && \
    chmod +x /app/run.sh

# Run the application
CMD ["/app/run.sh"]