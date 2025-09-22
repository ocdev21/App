m
FROM nikolaik/python-nodejs:latest

# Set working directory to root
WORKDIR /

# Copy entire project into container root directory
COPY . .

# Install NodeJS dependencies
RUN npm install

# Install Python dependencies
RUN pip install -r requirements.txt

# Expose port that your NodeJS app listens on
EXPOSE 3000

# Start the app using npm run dev
CMD ["npm", "run", "dev"]
