FROM public.ecr.aws/lambda/python:3.12

# Install system dependencies for PDF/document processing
RUN dnf install -y poppler-utils && dnf clean all

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy handler
COPY handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
