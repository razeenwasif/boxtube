// Common card styles used across components
export const cardStyles = {
  card: {
    display: 'flex',
    gap: 2,
    backgroundColor: 'rgba(33, 33, 33, 0.5)',
    borderRadius: '8px',
    overflow: 'hidden',
    border: '1px solid var(--border-color)',
    transition: 'all 0.3s ease',
    '&:hover': {
      transform: 'translateY(-2px)',
      boxShadow: 'var(--card-hover-shadow)',
      borderColor: 'var(--primary-color)',
    }
  },
  link: {
    display: 'flex',
    width: '100%',
    textDecoration: 'none'
  },
  title: {
    color: 'var(--text-primary)',
    transition: 'color 0.2s ease',
    '&:hover': { 
      color: 'var(--primary-color)' 
    }
  },
  channelName: {
    color: 'var(--text-secondary)',
    display: 'flex',
    alignItems: 'center',
    fontSize: '0.75rem',
  },
  verifiedIcon: {
    fontSize: 10,
    color: 'var(--primary-color)',
    marginLeft: '5px'
  }
}; 