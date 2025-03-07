import { Box, Typography, CircularProgress } from '@mui/material';
import PropTypes from 'prop-types';

/**
 * LoadingState Component
 * Displays a centered loading spinner with customizable message
 * @param {Object} props - Component props
 * @param {string} props.message - Loading message to display
 * @param {string} props.height - Height of the loading container
 */
const LoadingState = ({ message = 'Loading...', height = '50vh' }) => (
  <Box sx={{ 
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    height,
    flexDirection: 'column',
    gap: 2
  }}>
    <CircularProgress sx={{ color: 'var(--primary-color)' }} />
    <Typography variant="body1" color="var(--text-secondary)">
      {message}
    </Typography>
  </Box>
);

LoadingState.propTypes = {
  message: PropTypes.string,
  height: PropTypes.string
};

export default LoadingState; 