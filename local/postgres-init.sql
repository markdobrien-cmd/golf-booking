-- One database and one login per service, mirroring the RDS setup on AWS.
CREATE USER courses WITH PASSWORD 'courses';
CREATE DATABASE courses OWNER courses;
CREATE USER bookings WITH PASSWORD 'bookings';
CREATE DATABASE bookings OWNER bookings;
