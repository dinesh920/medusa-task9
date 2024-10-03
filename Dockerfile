# Use an official Node.js image as the base image
FROM node:18-alpine

# Set the working directory
WORKDIR /app

# Copy package.json and package-lock.json into the container first
COPY package*.json ./

# Install dependencies (including production dependencies)
RUN npm install --omit=dev

# Copy the rest of the application code
COPY . .

# Expose the Medusa default port
EXPOSE 9000

# Set the environment to production
ENV NODE_ENV=production

# Start the Medusa server
CMD ["npm", "run", "start"]


